# Autorización y alcance

Este instalador prepara herramientas que pueden decompilar APKs, instrumentar procesos, interceptar tráfico y observar datos de un dispositivo. La autorización debe incluir estación, APKs, emuladores/dispositivos, cuentas de prueba, redes, dominios, retención de capturas y ventana de trabajo.

La preparación del host no autoriza por sí misma a instalar un certificado proxy, adjuntar Frida, usar objection, capturar tráfico o analizar una aplicación de terceros. Declara cada fase requerida y conserva el expediente contractual fuera de Git.

| Fase | Autorización mínima |
|---|---|
| Estática | APK, hash, repositorio de entrega y retención de artefactos. |
| ADB | Serial/emulador y consentimiento para Depuración USB. |
| Dinámica | App de prueba, usuario de laboratorio y comandos permitidos. |
| Tráfico | Red aislada, proxy/certificado y dominios de prueba. |
| Trazas ADB | Serial/emulador, consentimiento para Depuración USB y retención de logs: logcat, dmesg y bugreport pueden contener datos personales o credenciales. |
| Auditoría ADB | Serial/emulador, consentimiento para Depuración USB y para la sonda TCP al puerto 5555 desde la red del laboratorio; retención de claves RSA autorizadas y de los hallazgos: las claves y los conteos de fugas son material sensible. |
| Conexión ADB | Serial/emulador y, para TCP, IP explícita del operador dentro del alcance de laboratorio; consentimiento para Depuración USB, reinicio del servidor ADB y `adb connect`. Un dispositivo `unauthorized` no se fuerza: la huella RSA se acepta en el teléfono. Retención del reporte de conexión: seriales y modelos son material sensible. |
| Alcance de laboratorio | Archivo `~/security-tools/scope` con los seriales y las IP/redes TCP autorizados; sin él la allowlist está inactiva y el operador responde por cada objetivo. |
| Analizar trazas | Material ya capturado o subido por el operador; para pedir un bugreport, serial/emulador y consentimiento para Depuración USB. El análisis es de solo lectura y solo muestra conteos y muestras de una línea; las muestras pueden contener material sensible y no se suben al repo. |
