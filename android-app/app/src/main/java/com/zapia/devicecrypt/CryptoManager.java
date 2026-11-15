package com.zapia.devicecrypt;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.KeyStore;
import java.security.SecureRandom;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Cifrado de archivos con AES/GCM + Android Keystore.
 *
 * <p>Formato {@code .crypt} (documentado en docs/encrypt-android.md):
 * {@code MAGIC "DCRYPT01" (8 bytes) + IV aleatorio (12 bytes) +
 * ciphertext con el tag GCM de 16 bytes al final} (así lo emite
 * {@link Cipher} en modo GCM). La clave AES de 256 bits vive en el
 * Android Keystore y nunca sale de él; si se borra la clave (o se
 * restablece el dispositivo) los archivos .crypt ya no se pueden
 * descifrar. Este formato NO es el .aes256 de Ubuntu (OpenSSL
 * AES-256-CBC + PBKDF2): no son intercambiables.</p>
 *
 * <p>Solo APIs públicas del SDK (minSdk 26): KeyStore, KeyGenerator,
 * KeyGenParameterSpec, Cipher AES/GCM/NoPadding y GCMParameterSpec.</p>
 */
public final class CryptoManager {

    public static final String KEY_ALIAS = "DeviceCryptKey";

    /** Cabecera del formato .crypt. */
    public static final byte[] MAGIC = {'D', 'C', 'R', 'Y', 'P', 'T', '0', '1'};

    private static final int IV_BYTES = 12;
    private static final int GCM_TAG_BITS = 128;
    private static final int BUFFER_BYTES = 8192;

    private CryptoManager() {
    }

    private static SecretKey getOrCreateKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (keyStore.containsAlias(KEY_ALIAS)) {
            return (SecretKey) keyStore.getKey(KEY_ALIAS, null);
        }
        KeyGenerator keyGenerator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        KeyGenParameterSpec spec = new KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build();
        keyGenerator.init(spec);
        return keyGenerator.generateKey();
    }

    /** Cifra {@code in} a {@code out} en formato .crypt. Devuelve los bytes cifrados. */
    public static long encrypt(InputStream in, OutputStream out) throws Exception {
        SecretKey key = getOrCreateKey();
        byte[] iv = new byte[IV_BYTES];
        new SecureRandom().nextBytes(iv);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_BITS, iv));
        out.write(MAGIC);
        out.write(iv);
        long written = MAGIC.length + IV_BYTES;
        byte[] buffer = new byte[BUFFER_BYTES];
        int read;
        while ((read = in.read(buffer)) != -1) {
            byte[] chunk = cipher.update(buffer, 0, read);
            if (chunk != null) {
                out.write(chunk);
                written += chunk.length;
            }
        }
        byte[] last = cipher.doFinal();
        if (last != null) {
            out.write(last);
            written += last.length;
        }
        out.flush();
        return written;
    }

    /** Descifra un .crypt. Si la cabecera no es válida o el tag GCM no coincide, falla. */
    public static long decrypt(InputStream in, OutputStream out) throws Exception {
        byte[] magic = new byte[MAGIC.length];
        if (in.read(magic) != MAGIC.length || !java.util.Arrays.equals(magic, MAGIC)) {
            throw new IOException("el archivo no es un .crypt válido (cabecera DCRYPT01 ausente)");
        }
        byte[] iv = new byte[IV_BYTES];
        if (in.read(iv) != IV_BYTES) {
            throw new IOException("archivo .crypt truncado (sin IV)");
        }
        SecretKey key = getOrCreateKey();
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_BITS, iv));
        long written = 0;
        byte[] buffer = new byte[BUFFER_BYTES];
        int read;
        while ((read = in.read(buffer)) != -1) {
            byte[] chunk = cipher.update(buffer, 0, read);
            if (chunk != null) {
                out.write(chunk);
                written += chunk.length;
            }
        }
        // doFinal verifica el tag GCM: si el archivo fue alterado o la
        // clave es otra, lanza AEADBadTagException aquí.
        byte[] last = cipher.doFinal();
        if (last != null) {
            out.write(last);
            written += last.length;
        }
        out.flush();
        return written;
    }
}
