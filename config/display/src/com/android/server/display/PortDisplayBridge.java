/*
 * Bridge from HyperOS's display feature HAL (vendor.xiaomi.hardware.displayfeature_aidl.IDisplayFeature) to
 * Android's own color pipeline on the Pixel.
 *
 * build.sh compiles this to smali and adds it to miui-services.jar.
 * DisplayFeatureManagerService Wrapper.setFeature / registerCallback and notifyDisplayFeature call here
 * (see ../*.methods.smali).
 *
 * Every call is logged to /data/system/port_display/setfeature.log (with stack).
 * Modes are applied on our own thread; callers (holding DFMS.mLock) return immediately:
 *   mode 0 vivid / 1 saturated -> ColorDisplayManager color mode 3 (automatic, sRGB/P3 per content; gamma tuned here)
 *   mode 2 original color      -> color mode 0 (natural, managed sRGB)
 *     Color mode 2 (unmanaged NATIVE) is avoided: it disables regamma and conflicts with port_gamma at 90Hz.
 *   color temperature (modes 0/1: 1 warm 2 natural 3 cool; ignored for original color) -> DTM white point (LV_WHITE)
 *   mode 3 reading mode (value = strength 0-255, cookie low byte != 0 = on) -> DTM color temperature (LV_EYE)
 *   mode 31 paper mode (0 full, 1 pale, 2 mono), mode 4 mono -> DTM saturation (LV_PAPER)
 *   other modes are only logged.
 * Tunables (read on the next call):
 *   persist.sys.port.disp.apply     0 = log only (default 1)
 *   persist.sys.port.disp.warm/cool RGB gains for warm / cool, "r,g,b" (linear light)
 *   persist.sys.port.disp.eye_k     color temperature (K) at strength 255; 0 = 6500K, linear in between
 *   persist.sys.port.disp.pale      saturation of pale mode (0-1)
 * Every entry point catches Throwable and only logs.
 */
package com.android.server.display;

import android.app.ActivityThread;
import android.content.Context;
import android.hardware.display.ColorDisplayManager;
import android.os.Binder;
import android.os.Debug;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemProperties;
import android.util.Slog;

import com.android.server.LocalServices;
import com.android.server.display.color.DisplayTransformManager;

import java.io.File;
import java.io.FileOutputStream;

public final class PortDisplayBridge {
    static final String TAG = "PortDisplayBridge";
    static final String DIR = "/data/system/port_display";
    static final String LOG = DIR + "/setfeature.log";

    // DTM levels, multiplied in ascending order (Android uses 100 night, 125 white balance, 150 saturation, 200 grayscale, 250 extra dim, 300 inversion)
    static final int LV_EYE = 105;
    static final int LV_WHITE = 110;
    static final int LV_PAPER = 160;

    static final int COLOR_MODE_NATURAL = 0;
    static final int COLOR_MODE_AUTOMATIC = 3;

    // last state received from Xiaomi's side (-1 = not yet, leave alone)
    static int sColorMode = -1;
    static int sCt = 2;
    static int sEye = 0;
    static int sPaper = 0;
    static int sMono = 0;

    static Handler sHandler;
    static boolean sPending;
    static int sRetries;

    static final class Apply implements Runnable {
        public void run() { apply(); }
    }
    static final Apply APPLY = new Apply();

    public static void setFeature(int display, int mode, int value, int cookie) {
        feature("setFeature", display, mode, value, cookie);
        try {
            if (display == 0) handle(mode, value, cookie);
        } catch (Throwable e) {
            Slog.w(TAG, "handle failed", e);
        }
    }

    public static void notifyFeature(int display, int mode, int value, int cookie) {
        feature("notifyDisplayFeature", display, mode, value, cookie);
    }

    public static void registerCallback(int display, Object cb) {
        record("registerCallback display=" + display + " callback="
                + (cb == null ? "null" : cb.getClass().getName()));
    }

    static void feature(String what, int d, int mode, int value, int cookie) {
        record(what + " display=" + d + " mode=" + mode + " value=" + value + " cookie=" + cookie);
    }

    static void record(String what) {
        try {
            String line = System.currentTimeMillis() + " " + what + " uid=" + Binder.getCallingUid()
                    + " pid=" + Binder.getCallingPid() + " thread=" + Thread.currentThread().getName()
                    + " at=" + Debug.getCallers(8);
            Slog.i(TAG, line);
            new File(DIR).mkdirs();
            File f = new File(LOG);
            if (f.length() > 1048576) f.renameTo(new File(LOG + ".old"));
            FileOutputStream o = new FileOutputStream(f, true);   // O_APPEND, single write, no lock
            try {
                o.write(line.concat("\n").getBytes());
            } finally {
                o.close();
            }
        } catch (Throwable e) {
            Slog.w(TAG, "record failed", e);
        }
    }

    static synchronized void handle(int mode, int value, int cookie) {
        switch (mode) {
            case 0:   // vivid (adaptive)
            case 1:   // saturated (hidden in the simplified color styles)
                sColorMode = COLOR_MODE_AUTOMATIC;
                sCt = value;
                break;
            case 2:   // original color
                sColorMode = COLOR_MODE_NATURAL;
                sCt = value;
                break;
            case 3:   // reading mode
                sEye = (cookie & 0xff) != 0 ? value : 0;
                break;
            case 4:   // mono (no entry in Settings)
                sMono = value;
                break;
            case 31:  // paper mode
                sPaper = value;
                break;
            default:
                return;
        }
        schedule(0);
    }

    static synchronized void schedule(long delay) {
        if (sPending && delay == 0) return;
        if (sHandler == null) {
            HandlerThread t = new HandlerThread(TAG);
            t.start();
            sHandler = new Handler(t.getLooper());
        }
        sPending = true;
        sHandler.postDelayed(APPLY, delay);
    }

    static void apply() {
        int colorMode, ct, eye, paper, mono;
        synchronized (PortDisplayBridge.class) {
            sPending = false;
            colorMode = sColorMode; ct = sCt; eye = sEye; paper = sPaper; mono = sMono;
        }
        try {
            if (!SystemProperties.getBoolean("persist.sys.port.disp.apply", true)) return;

            if (colorMode >= 0) {
                Context c = ActivityThread.currentApplication();
                ColorDisplayManager cdm = c.getSystemService(ColorDisplayManager.class);
                if (cdm.getColorMode() != colorMode) {
                    cdm.setColorMode(colorMode);
                    Slog.i(TAG, "color mode -> " + colorMode);
                }
            }

            DisplayTransformManager dtm = LocalServices.getService(DisplayTransformManager.class);
            if (dtm == null) throw new IllegalStateException("DisplayTransformManager not ready");

            float[] white = null;
            if (colorMode == COLOR_MODE_AUTOMATIC && ct == 1) {
                white = diag(prop3("persist.sys.port.disp.warm", 1.0f, 0.93f, 0.82f));
            } else if (colorMode == COLOR_MODE_AUTOMATIC && ct == 3) {
                white = diag(prop3("persist.sys.port.disp.cool", 0.88f, 0.94f, 1.0f));
            }
            dtm.setColorMatrix(LV_WHITE, white);

            float[] eyeM = null;
            if (eye > 0) {
                int minK = SystemProperties.getInt("persist.sys.port.disp.eye_k", 3400);
                float k = 6500f - (6500f - minK) * Math.min(eye, 255) / 255f;
                eyeM = diag(cctToLinearRgb(k));
            }
            dtm.setColorMatrix(LV_EYE, eyeM);

            float[] paperM = null;
            if (mono != 0 || paper == 2) {
                paperM = saturation(0f);
            } else if (paper == 1) {
                paperM = saturation(propF("persist.sys.port.disp.pale", 0.5f));
            }
            dtm.setColorMatrix(LV_PAPER, paperM);
            sRetries = 0;
        } catch (Throwable e) {
            // ColorDisplayService / DTM may not be up early in boot: retry every 5 s, up to 12 times
            Slog.w(TAG, "apply failed (retry " + sRetries + ")", e);
            if (sRetries++ < 12) schedule(5000);
        }
    }

    static float[] diag(float[] rgb) {
        float[] m = new float[16];
        m[0] = rgb[0];
        m[5] = rgb[1];
        m[10] = rgb[2];
        m[15] = 1f;
        return m;
    }

    // same formula as Android's GlobalSaturationTintController (column-major 4x4)
    static float[] saturation(float s) {
        float d = 1f - s;
        float r = 0.231f * d, g = 0.715f * d, b = 0.072f * d;
        float[] m = new float[16];
        m[0] = r + s; m[1] = r;     m[2] = r;
        m[4] = g;     m[5] = g + s; m[6] = g;
        m[8] = b;     m[9] = b;     m[10] = b + s;
        m[15] = 1f;
        return m;
    }

    // blackbody -> sRGB (Tanner Helland approximation), normalized to 6500K, then linearized
    static float[] cctToLinearRgb(float k) {
        float[] c = helland(k), w = helland(6500f);
        float[] out = new float[3];
        for (int i = 0; i < 3; i++) {
            float v = Math.max(0f, Math.min(1f, c[i] / w[i]));
            out[i] = (float) Math.pow(v, 2.2);
        }
        return out;
    }

    static float[] helland(float kelvin) {
        double t = kelvin / 100.0;
        double r, g, b;
        if (t <= 66) {
            r = 255;
            g = 99.4708025861 * Math.log(t) - 161.1195681661;
        } else {
            r = 329.698727446 * Math.pow(t - 60, -0.1332047592);
            g = 288.1221695283 * Math.pow(t - 60, -0.0755148492);
        }
        if (t >= 66) b = 255;
        else if (t <= 19) b = 0;
        else b = 138.5177312231 * Math.log(t - 10) - 305.0447927307;
        return new float[] { clamp(r), clamp(g), clamp(b) };
    }

    static float clamp(double v) {
        return (float) Math.max(0, Math.min(255, v));
    }

    static float[] prop3(String key, float r, float g, float b) {
        float[] def = { r, g, b };
        try {
            String s = SystemProperties.get(key, "");
            if (s.isEmpty()) return def;
            String[] p = s.split(",");
            return new float[] { Float.parseFloat(p[0].trim()), Float.parseFloat(p[1].trim()),
                    Float.parseFloat(p[2].trim()) };
        } catch (Throwable e) {
            return def;
        }
    }

    static float propF(String key, float def) {
        try {
            String s = SystemProperties.get(key, "");
            return s.isEmpty() ? def : Float.parseFloat(s.trim());
        } catch (Throwable e) {
            return def;
        }
    }
}
