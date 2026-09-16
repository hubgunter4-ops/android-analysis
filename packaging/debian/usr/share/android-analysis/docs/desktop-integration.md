# Integración con el menú de aplicaciones de Ubuntu y Kali

El paquete incluye un icono SVG y un archivo `.desktop` para que **Android Analysis** aparezca en el menú de aplicaciones de Ubuntu y Kali Linux. Ambas distribuciones utilizan el formato Debian para esta integración.

## Estructura

```text
packaging/debian/
├── DEBIAN/
│   ├── control
│   └── postinst
└── usr/
    ├── bin/android-analysis
    └── share/
        ├── applications/android-analysis.desktop
        └── icons/hicolor/scalable/apps/android-analysis.svg
```

## Preparar el árbol Debian

Desde la raíz del repositorio:

```bash
rm -rf packaging/debian/usr/share/android-analysis
mkdir -p packaging/debian/usr/share/android-analysis
cp -r src docs install.sh packaging/debian/usr/share/android-analysis/
chmod 755 packaging/debian/usr/bin/android-analysis
chmod 755 packaging/debian/DEBIAN/postinst
```

El archivo `.desktop` usa `Icon=android-analysis`, que corresponde al icono azul compatible con Kali instalado en:

```text
/usr/share/icons/hicolor/scalable/apps/android-analysis.svg
```

No se debe poner la ruta absoluta en `Icon`; usar el nombre permite que el tema de iconos de Ubuntu lo encuentre correctamente.

## Construir e instalar

```bash
dpkg-deb --build packaging/debian android-analysis-toolchain_2.1.0_all.deb
sudo apt install ./android-analysis-toolchain_2.1.0_all.deb
```

Después de instalar, busca **Android Analysis** en el menú de aplicaciones o ejecútala con:

```bash
android-analysis
```

Para refrescar manualmente la base del menú, si fuera necesario:

```bash
sudo update-desktop-database /usr/share/applications
```

## Campos importantes del `.desktop`

- `Exec=android-analysis`: ejecuta el lanzador instalado.
- `Icon=android-analysis`: referencia el SVG por nombre de tema.
- `Terminal=false`: abre la GUI sin terminal adicional.
- `Categories=Development;Security;System;`: clasifica la aplicación.
- `StartupNotify=true`: permite a Ubuntu mostrar el estado de inicio.

El paquete declara `python3-tk` y `android-tools-adb` como dependencias. El instalador de la toolchain continúa siendo responsable de preparar las herramientas adicionales del laboratorio.
