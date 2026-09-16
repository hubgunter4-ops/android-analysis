# Autorización y alcance

Este instalador prepara herramientas que pueden decompilar APKs, instrumentar procesos, interceptar tráfico y observar datos de un dispositivo. La autorización debe incluir estación, APKs, emuladores/dispositivos, cuentas de prueba, redes, dominios, retención de capturas y ventana de trabajo.

La preparación del host no autoriza por sí misma a instalar un certificado proxy, adjuntar Frida, usar objection, capturar tráfico o analizar una aplicación de terceros. Declara cada fase requerida y conserva el expediente contractual fuera de Git.

| Fase | Autorización mínima |
|---|---|
| Estática | APK, hash, repositorio de entrega y retención de artefactos. |
| ADB | Serial/emulador y consentimiento para Depuración USB. |
| Dinámica | App de prueba, usuario de laboratorio y comandos permitidos. |
| Tráfico | Red aislada, proxy/certificado y dominios de prueba. |
