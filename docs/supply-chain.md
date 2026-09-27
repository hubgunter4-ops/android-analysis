# Cadena de suministro

El instalador descarga paquetes del sistema, JADX v1.5.6 por GitHub y clona dex2jar/MobSF en commits fijados. Los orígenes están codificados en el script y las descargas externas se realizan por HTTPS con `curl --fail`, `--proto '=https'` y TLS 1.2 o superior.

JADX se verifica obligatoriamente con SHA-256 antes de descomprimirlo. El valor fijado para v1.5.6 es `545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974`. `requirements.in` declara las dependencias directas y `requirements.lock` fija las versiones transitivas y hashes; el instalador usa `pip --require-hashes`.

Los clones se realizan con profundidad 1 en la revisión aprobada y no se ejecutan scripts de terceros automáticamente. El instalador rechaza una revisión distinta en un destino existente. Revisa cambios de release antes de actualizar y conserva un inventario de:

| Campo | Registro |
|---|---|
| URL | Origen exacto del paquete o repositorio. |
| Versión | Release, commit o paquete instalado. |
| SHA-256 | Hash del artefacto cuando esté disponible. |
| Fecha | Momento de instalación. |
| Revisión | Persona que aprobó el componente. |
