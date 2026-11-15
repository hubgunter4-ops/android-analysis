package com.zapia.devicecrypt;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.admin.DevicePolicyManager;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;

/**
 * DeviceCrypt 1.0 — cifra y descifra archivos que el usuario elige,
 * con AES/GCM + Android Keystore (ver {@link CryptoManager}).
 *
 * <p>LÍMITE HONESTO: esta app NO activa ni desactiva el cifrado del
 * sistema. Solo muestra su estado con
 * {@link DevicePolicyManager#getStorageEncryptionStatus()} (API pública)
 * y cifra archivos concretos. Desde Android 10 el cifrado del sistema
 * es por archivos (FBE) y viene activo de fábrica.</p>
 *
 * <p>Solo APIs públicas del SDK (minSdk 26): DevicePolicyManager, SAF
 * (ACTION_OPEN_DOCUMENT / ACTION_CREATE_DOCUMENT), DocumentsContract y
 * ContentResolver. Se usa startActivityForResult (obsoleto desde API 30
 * pero público y vigente) para no depender de AndroidX: la app no tiene
 * dependencias externas. El trabajo pesado corre en un hilo aparte y
 * la interfaz se actualiza con runOnUiThread.</p>
 *
 * <p>Toda la pantalla va dentro de un ScrollView: nada queda fuera de
 * alcance en pantallas altas.</p>
 */
public class MainActivity extends Activity {

    private static final int REQ_PICK_ENCRYPT = 1;
    private static final int REQ_PICK_DECRYPT = 2;
    private static final int REQ_CREATE_OUTPUT = 3;

    private TextView statusText;
    private TextView selectedText;
    private TextView logText;
    private TextView historyText;
    private Button cryptButton;

    private Uri pendingInputUri;
    private String pendingInputName;
    private String pendingMode; // "encrypt" o "decrypt"
    private boolean working;
    private final ArrayList<String> sessionOutputs = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        statusText = findViewById(R.id.status_text);
        selectedText = findViewById(R.id.selected_text);
        logText = findViewById(R.id.log_text);
        historyText = findViewById(R.id.history_text);
        cryptButton = findViewById(R.id.btn_crypt);
        Button refreshButton = findViewById(R.id.btn_refresh_status);
        Button pickEncryptButton = findViewById(R.id.btn_pick_encrypt);
        Button pickDecryptButton = findViewById(R.id.btn_pick_decrypt);

        refreshButton.setOnClickListener(v -> refreshEncryptionStatus());
        pickEncryptButton.setOnClickListener(v -> pickFile(REQ_PICK_ENCRYPT));
        pickDecryptButton.setOnClickListener(v -> pickFile(REQ_PICK_DECRYPT));
        cryptButton.setOnClickListener(v -> chooseOutput());
        cryptButton.setEnabled(false);
        refreshEncryptionStatus();
        log("DeviceCrypt 1.0 lista. Elige un archivo para cifrar o descifrar.");
    }

    private void refreshEncryptionStatus() {
        DevicePolicyManager dpm =
                (DevicePolicyManager) getSystemService(Context.DEVICE_POLICY_SERVICE);
        int status = dpm == null
                ? DevicePolicyManager.ENCRYPTION_STATUS_UNSUPPORTED
                : dpm.getStorageEncryptionStatus();
        String text;
        switch (status) {
            case DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE:
                text = "CIFRADO — el almacenamiento está cifrado (activo).";
                break;
            case DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_DEFAULT_KEY:
                text = "CIFRADO — activo con clave por defecto del sistema.";
                break;
            case DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_PER_USER:
                text = "CIFRADO — activo por usuario.";
                break;
            case DevicePolicyManager.ENCRYPTION_STATUS_INACTIVE:
                text = "SIN CIFRAR — el cifrado del sistema está inactivo.\n"
                        + "Esta app no puede activarlo: ve a Ajustes > Seguridad "
                        + "> Cifrado y credenciales y sigue el asistente del sistema.";
                break;
            case DevicePolicyManager.ENCRYPTION_STATUS_UNSUPPORTED:
            default:
                text = "DESCONOCIDO — el dispositivo no informa del estado "
                        + "del cifrado (ENCRYPTION_STATUS_UNSUPPORTED).";
                break;
        }
        statusText.setText("Cifrado del sistema: " + text);
    }

    @SuppressWarnings("deprecation")
    private void pickFile(int requestCode) {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, requestCode);
    }

    @SuppressWarnings("deprecation")
    private void chooseOutput() {
        if (pendingInputUri == null || pendingMode == null) {
            return;
        }
        String suggested;
        if ("encrypt".equals(pendingMode)) {
            suggested = pendingInputName + ".crypt";
        } else if (pendingInputName.endsWith(".crypt")) {
            suggested = pendingInputName.substring(0, pendingInputName.length() - 6);
        } else {
            suggested = pendingInputName + ".dec";
        }
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/octet-stream");
        intent.putExtra(Intent.EXTRA_TITLE, suggested);
        startActivityForResult(intent, REQ_CREATE_OUTPUT);
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            return;
        }
        Uri uri = data.getData();
        if (requestCode == REQ_PICK_ENCRYPT || requestCode == REQ_PICK_DECRYPT) {
            pendingInputUri = uri;
            pendingInputName = displayName(uri);
            pendingMode = requestCode == REQ_PICK_ENCRYPT ? "encrypt" : "decrypt";
            selectedText.setText("Archivo: " + pendingInputName);
            cryptButton.setText("encrypt".equals(pendingMode)
                    ? "Cifrar archivo" : "Descifrar archivo");
            cryptButton.setEnabled(true);
            log("Seleccionado para " + ("encrypt".equals(pendingMode) ? "cifrar" : "descifrar")
                    + ": " + pendingInputName);
        } else if (requestCode == REQ_CREATE_OUTPUT) {
            runCrypto(uri);
        }
    }

    private String displayName(Uri uri) {
        try (Cursor cursor = getContentResolver().query(
                uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) {
                    return cursor.getString(index);
                }
            }
        } catch (Exception ignored) {
            // Sin nombre legible: se usa el último segmento de la URI.
        }
        String last = uri.getLastPathSegment();
        return last == null ? "archivo" : last;
    }

    private void runCrypto(Uri outputUri) {
        if (working || pendingInputUri == null || pendingMode == null) {
            return;
        }
        working = true;
        cryptButton.setEnabled(false);
        final Uri inputUri = pendingInputUri;
        final String inputName = pendingInputName;
        final String mode = pendingMode;
        log("Procesando " + inputName + " (" + mode + ")…");
        new Thread(() -> {
            try (InputStream in = getContentResolver().openInputStream(inputUri);
                 OutputStream out = getContentResolver().openOutputStream(outputUri)) {
                if (in == null || out == null) {
                    throw new IllegalStateException("no se pudo abrir el archivo elegido");
                }
                long bytes = "encrypt".equals(mode)
                        ? CryptoManager.encrypt(in, out)
                        : CryptoManager.decrypt(in, out);
                runOnUiThread(() -> {
                    String done = ("encrypt".equals(mode) ? "Cifrado: " : "Descifrado: ")
                            + inputName + " (" + bytes + " bytes)";
                    log(done);
                    sessionOutputs.add(done);
                    renderHistory();
                    Toast.makeText(this, done, Toast.LENGTH_LONG).show();
                    if ("encrypt".equals(mode)) {
                        askDeleteOriginal(inputUri, inputName);
                    }
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    log("Error: " + e.getMessage());
                    Toast.makeText(this, "Error: " + e.getMessage(), Toast.LENGTH_LONG).show();
                });
            } finally {
                runOnUiThread(() -> {
                    working = false;
                    cryptButton.setEnabled(pendingInputUri != null);
                });
            }
        }).start();
    }

    /** Borrar el original solo con confirmación explícita del usuario. */
    private void askDeleteOriginal(Uri inputUri, String inputName) {
        new AlertDialog.Builder(this)
                .setTitle("Borrar el original?")
                .setMessage("El archivo cifrado ya está guardado. ¿Borrar el original sin cifrar ("
                        + inputName + ")? Sin él no se puede recuperar si pierdes la clave.")
                .setPositiveButton("Borrar original", (dialog, which) -> {
                    boolean deleted;
                    try {
                        deleted = DocumentsContract.deleteDocument(
                                getContentResolver(), inputUri);
                    } catch (Exception e) {
                        deleted = false;
                        log("No se pudo borrar el original: " + e.getMessage());
                    }
                    log(deleted ? "Original borrado: " + inputName
                            : "No se pudo borrar el original: " + inputName);
                })
                .setNegativeButton("Conservar original", (dialog, which) ->
                        log("Original conservado: " + inputName))
                .show();
    }

    private void renderHistory() {
        StringBuilder builder = new StringBuilder();
        for (String item : sessionOutputs) {
            builder.append("· ").append(item).append("\n");
        }
        historyText.setText(builder.length() == 0
                ? "Aún no hay archivos .crypt en esta sesión."
                : builder.toString());
    }

    private void log(String line) {
        String current = logText.getText().toString();
        String next = current + line + "\n";
        // Registro acotado: no dejar que un log largo congele la pantalla.
        if (next.length() > 3000) {
            next = next.substring(next.length() - 3000);
        }
        logText.setText(next);
    }
}
