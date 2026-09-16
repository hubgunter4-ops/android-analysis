# Cadena de suministro

El instalador descarga paquetes del sistema, un release de JADX por GitHub y clona dex2jar/MobSF. Los orígenes están codificados en el script y las descargas externas se realizan por HTTPS con `curl --fail`, `--proto '=https'` y TLS 1.2 o superior.

JADX admite verificación SHA-256 mediante `JADX_SHA256`. Si el proyecto publica checksums para una versión concreta, obtén el valor por un canal independiente y expórtalo antes de instalar. Sin ese valor, la protección es de transporte y origen, no una atestación criptográfica completa.

Los clones se realizan con profundidad 1 y no se ejecutan scripts de terceros automáticamente. Revisa cambios de release, fija una versión aprobada para entornos productivos y conserva un inventario de:

| Campo | Registro |
|---|---|
| URL | Origen exacto del paquete o repositorio. |
| Versión | Release, commit o paquete instalado. |
| SHA-256 | Hash del artefacto cuando esté disponible. |
| Fecha | Momento de instalación. |
| Revisión | Persona que aprobó el componente. |
