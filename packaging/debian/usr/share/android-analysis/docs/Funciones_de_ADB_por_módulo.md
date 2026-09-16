# Funciones de ADB por módulo

_Lista de nombres de comandos y funciones de Android Debug Bridge (ADB), organizada por módulo._

---

## Comandos generales

- `devices`
- `help`
- `version`

## Conectividad y red

- `connect`
- `disconnect`
- `pair`
- `forward`
- `reverse`
- `mdns check`
- `mdns services`

## Transferencia de archivos

- `push`
- `pull`
- `sync`

## Shell remoto

- `shell`
- `emu`

## Instalación de aplicaciones

- `install`
- `install-multiple`
- `install-multi-package`
- `uninstall`

## Depuración

- `bugreport`
- `jdwp`
- `logcat`
- `server-status`

## Seguridad

- `disable-verity`
- `enable-verity`
- `keygen`

## Automatización y scripting

- `wait-for-device`
- `wait-for-recovery`
- `wait-for-rescue`
- `wait-for-sideload`
- `wait-for-bootloader`
- `wait-for-disconnect`
- `get-state`
- `get-serialno`
- `get-devpath`
- `remount`
- `reboot`
- `sideload`
- `root`
- `unroot`
- `usb`
- `tcpip`

## Gestión del servidor ADB

- `start-server`
- `kill-server`
- `reconnect`
- `server nodaemon`

## USB

- `attach`
- `detach`

## Funciones y características

- `host-features`
- `features`

## Activity Manager (`am`)

- `start`
- `startservice`
- `start-foreground-service`
- `stopservice`
- `force-stop`
- `kill`
- `kill-all`
- `broadcast`
- `instrument`
- `profile`
- `dumpheap`
- `set-debug-app`
- `clear-debug-app`
- `bug-report`
- `monitor`
- `hang`
- `screen-compat`
- `display-size`
- `display-density`
- `stack`
- `task`
- `lock-task`
- `stop-app`
- `write`
- `attach-agent`
- `idle-maintenance`
- `screen-rotate`
- `to-uri`
- `to-intent-uri`
- `to-app-uri`
- `switch-user`
- `get-current-user`
- `start-user`
- `unlock-user`
- `stop-user`
- `is-user-stopped`
- `get-started-user-state`
- `trace-ipc`
- `untrack-associations`
- `set-watch-heap`
- `isolated`
- `set-inactive`
- `get-inactive`
- `set-stop-user-on-switch`
- `set-bg-restriction-level`
- `get-bg-restriction-level`
- `supports-multiwindow`
- `supports-split-screen-multi-window`
- `update-appinfo`
- `write-settings`
- `get-config`
- `suspend`
- `unsuspend`
- `compact`
- `refresh-settings-cache`
- `get-standby-bucket`
- `set-standby-bucket`
- `set-standby-bucket-by-pkg`
- `get-standby-bucket-by-pkg`
- `set-foreground-service-delegate`
- `set-foreground-service-delegate-shell`
- `clear-exit-info`
- `get-exit-info`
- `set-parcel-size`
- `get-parcel-size`
- `set-inactive`
- `get-inactive`
- `set-bg-abusive-uids`
- `clear-bg-abusive-uids`
- `get-bg-abusive-uids`
- `set-bg-activity-starts-enabled`

## Package Manager (`pm`)

- `install`
- `install-create`
- `install-write`
- `install-commit`
- `install-abandon`
- `install-existing`
- `install-existing-user`
- `install-multi-package`
- `install-multi-package-create`
- `install-multi-package-write`
- `install-multi-package-add-session`
- `install-multi-package-commit`
- `uninstall`
- `clear`
- `enable`
- `disable`
- `disable-user`
- `disable-until-used`
- `default-state`
- `hide`
- `unhide`
- `suspend`
- `unsuspend`
- `grant`
- `revoke`
- `reset-permissions`
- `set-permission-flags`
- `clear-permission-flags`
- `get-max-running-users`
- `set-install-location`
- `get-install-location`
- `set-home-activity`
- `set-installer`
- `set-app-link`
- `get-app-link`
- `get-privapp-permissions`
- `get-oem-permissions`
- `get-moduleinfo`
- `get-stagedsessions`
- `list packages`
- `list permission-groups`
- `list permissions`
- `list instrumentation`
- `list features`
- `list libraries`
- `list users`
- `list shared-users`
- `list bridges`
- `list staged-sessions`
- `list dnssd`
- `path`
- `dump`
- `query-activities`
- `query-services`
- `query-receivers`
- `resolve-activity`
- `set-home-activity`
- `set-harmful-app-warning`
- `get-harmful-app-warning`
- `set-distracting-restriction`
- `clear-distracting-restriction`
- `get-privapp-permissions`
- `trim-caches`
- `create-user`
- `remove-user`
- `rename-user`
- `set-user-restriction`
- `get-user-restriction`
- `set-user-restriction-exemptions`
- `get-user-restriction-exemptions`
- `set-user-restriction-exemptions`
- `make-user-inactive`
- `set-user-visible`
- `is-user-visible`
- `set-user-enabled`
- `set-user-ephemeral`
- `set-user-restriction`
- `set-user-profile`
- `set-user-prop`
- `get-stagedsessions`
- `rollback-app`
- `snapshot-profile`
- `restorecon`
- `set-active-admin`
- `set-device-owner`
- `set-profile-owner`
- `remove-active-admin`
- `clear-role-holders`
- `get-role-holders`
- `query-activities`
- `query-services`
- `query-receivers`
- `resolve-activity`
- `get-moduleinfo`
- `has-feature`
- `is-package-device-admin`
- `list-unknown-sources`

## Device Policy Manager (`dpm`)

- `set-active-admin`
- `set-device-owner`
- `set-profile-owner`
- `remove-active-admin`
- `clear-freeze-period-record`
- `set-organization-id`
- `set-profile-name`
- `set-device-owner-on-user`
- `set-system-update-policy`
- `set-safe-mode-admin`
- `set-user-restriction`
- `set-device-policy-management-role-holder`
- `set-financed-device-owner`
- `set-device-owner-using-persisted-state`
- `set-test-harness-mode`
- `is-operation-safe`
- `list-owners`
- `list-policy-exempt-apps`

## Captura de pantalla

- `screencap`

## Grabación de pantalla

- `screenrecord`

## Perfiles ART

- `profman`
- `cmd art dump-profiles`
- `cmd package compile`

## Reinicio de dispositivos de prueba

- `cmd testharness enable`
- `am instrument`
- `pm clear`
- `settings delete`
- `svc wifi disable`
- `svc data disable`

## SQLite

- `sqlite3`

## Registro del sistema

- `logcat`

## Administrador de servicios (`cmd`)

- `cmd activity`
- `cmd alarm`
- `cmd appops`
- `cmd battery`
- `cmd connectivity`
- `cmd device_policy`
- `cmd diskstats`
- `cmd dropbox`
- `cmd game`
- `cmd input`
- `cmd jobscheduler`
- `cmd location`
- `cmd media_session`
- `cmd netpolicy`
- `cmd netstats`
- `cmd package`
- `cmd power`
- `cmd role`
- `cmd stats`
- `cmd statusbar`
- `cmd telecom`
- `cmd thermalservice`
- `cmd uimode`
- `cmd usb`
- `cmd vibrator_manager`
- `cmd wallpaper`
- `cmd wifi`
- `cmd window`

## Utilidades del sistema (`toybox`)

- `alias`
- `basename`
- `blockdev`
- `cal`
- `cat`
- `chcon`
- `chgrp`
- `chmod`
- `chown`
- `cksum`
- `clear`
- `cmp`
- `comm`
- `cp`
- `cut`
- `date`
- `dd`
- `df`
- `diff`
- `dirname`
- `dmesg`
- `du`
- `echo`
- `env`
- `expand`
- `expr`
- `fallocate`
- `false`
- `find`
- `flock`
- `fmt`
- `fold`
- `free`
- `getconf`
- `grep`
- `groups`
- `head`
- `hexdump`
- `hostname`
- `id`
- `ifconfig`
- `inotifyd`
- `insmod`
- `ionice`
- `kill`
- `killall`
- `ln`
- `load_policy`
- `log`
- `losetup`
- `ls`
- `lsattr`
- `lsmod`
- `lsof`
- `md5sum`
- `mkdir`
- `mkfifo`
- `mknod`
- `mkswap`
- `more`
- `mount`
- `mv`
- `nc`
- `netstat`
- `nice`
- `nohup`
- `od`
- `paste`
- `pgrep`
- `pidof`
- `pkill`
- `pmap`
- `printenv`
- `printf`
- `ps`
- `pwd`
- `readlink`
- `realpath`
- `renice`
- `reset`
- `restorecon`
- `rm`
- `rmdir`
- `rmmod`
- `run-as`
- `sed`
- `sendevent`
- `seq`
- `setenforce`
- `setprop`
- `sha1sum`
- `sha256sum`
- `sleep`
- `sort`
- `split`
- `stat`
- `strings`
- `stty`
- `su`
- `sum`
- `sync`
- `tail`
- `sum`
- `sync`
- `tail`
- `tee`
- `test`
- `time`
- `timeout`
- `top`
- `touch`
- `tr`
- `traceroute`
- `true`
- `tty`
- `ulimit`
- `umount`
- `uname`
- `uniq`
- `uptime`
- `usleep`
- `vdc`
- `vmstat`
- `wc`
- `which`
- `whoami`
- `xargs`
- `yes`

## Referencias

[1]: https://developer.android.com/tools/adb "Android Debug Bridge (adb) — Android Developers"

[2]: https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/master/docs/user/adb.1.md "ADB(1) Man Page — Android Open Source Project"
