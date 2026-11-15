/*
 * Receives HyperOS performance calls (Xiaomi IUniperf, Qualcomm perf2 IPerf). Logs only, executes nothing.
 *
 *
 * build.sh compiles this to smali and adds it to services.jar.
 * Entry points:
 *   - Xiaomi UniperfClient (miui-services.jar, system_server only) method bodies call the static u* methods
 *     (config/perf/src/com/xiaomi/uniperf/UniperfClient.java -> UniperfClient.methods.smali)
 *   - Qualcomm com.qualcomm.qti.Performance (QPerformance.jar, boot classpath, every process) perf* methods call
 *     com.qualcomm.qti.PortPerfHook; start() (from PortPerfBridge.start()) puts this instance in PortPerfHook.sHook.
 *     In app processes nobody sets it and Performance fails right away without a service lookup.
 *
 * Logs (/data/system/port_perf/):
 *   calls.log      one line per call: time, source, method, args, thread, caller (rotated to calls.log.old at 1 MB)
 *   summary.txt    counts per (source, method, args, caller) for this boot, written 60 s after changes; previous one kept as summary.prev.txt
 * Return values:
 *   Uniperf: getUniperfservice() = true (Xiaomi policies keep running), boosts / limits return increasing fake handles,
 *            release returns true, perfGetProp returns the caller's default, perfGetFeedback returns -1.
 *   Performance: everything fails (-1), perfGetProp returns the default, as with no perf service.
 * persist.sys.port.perf.log=0 turns logging off (return values unchanged).
 * Every entry point catches Throwable and only logs.
 */
package com.android.server.power;

import android.content.Context;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemProperties;
import android.util.Slog;

import java.io.File;
import java.io.FileOutputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BiFunction;

public final class PortPerfHint implements BiFunction<String, Object[], Object> {
    static final String TAG = "PortPerfHint";
    static final String DIR = "/data/system/port_perf";
    static final String LOG = DIR + "/calls.log";
    static final String SUM = DIR + "/summary.txt";
    static final int LOG_MAX = 1048576;
    static final int SUM_MAX_KEYS = 3000;
    static final long SUM_DELAY = 60000;

    static final AtomicLong sHandle = new AtomicLong();
    static final Integer FAIL = Integer.valueOf(-1);
    static Handler sHandler;
    static final HashMap<String, Stat> sStats = new HashMap<>();
    static boolean sSumPending;
    static final long sBoot = System.currentTimeMillis();

    static final class Stat {
        long count;
        long first;
        long last;
        String lastPkg;
    }

    static final class Rec implements Runnable {
        final long when;
        final String line;
        final String key;
        final String pkg;

        Rec(long when, String line, String key, String pkg) {
            this.when = when;
            this.line = line;
            this.key = key;
            this.pkg = pkg;
        }

        public void run() {
            write(when, line, key, pkg);
        }
    }

    static final class WriteSummary implements Runnable {
        public void run() {
            summary();
        }
    }

    static final WriteSummary WRITE_SUMMARY = new WriteSummary();

    // ---------------------------------------------------------------- start

    /** Called by PortPerfBridge.start() (PowerManagerService.onBootPhase 500). */
    public static void start(Context c) {
        try {
            handler();
            com.qualcomm.qti.PortPerfHook.sHook = new PortPerfHint();
            Slog.i(TAG, "Performance hook installed");
        } catch (Throwable e) {
            // NoClassDefFoundError when QPerformance.jar is not patched
            Slog.w(TAG, "Performance hook not installed: " + e);
        }
    }

    static synchronized Handler handler() {
        if (sHandler == null) {
            HandlerThread t = new HandlerThread(TAG);
            t.start();
            sHandler = new Handler(t.getLooper());
            sHandler.post(new Runnable() {
                public void run() {
                    try {
                        new File(DIR).mkdirs();
                        File s = new File(SUM);
                        if (s.exists()) s.renameTo(new File(DIR + "/summary.prev.txt"));
                    } catch (Throwable e) {
                        Slog.w(TAG, "init failed", e);
                    }
                }
            });
        }
        return sHandler;
    }

    // ---------------------------------------------------------------- Xiaomi UniperfClient

    public static long uHint(long handle, int hint, int type, int duration, String data) {
        long h = sHandle.incrementAndGet();
        record("uniperf", "hint", "hint=0x" + Integer.toHexString(hint) + " type=" + type + " dur=" + duration,
                "old=" + handle + " new=" + h, data);
        return h;
    }

    /** UniperfLockAcquire / UniperfSetFreqlevel. */
    public static long uLock(String method, long handle, int duration, int[] args) {
        long h = sHandle.incrementAndGet();
        record("uniperf", method, "dur=" + duration + " args=" + hexArgs(args),
                "old=" + handle + " new=" + h, null);
        return h;
    }

    public static boolean uRelease(long handle) {
        record("uniperf", "release", "", "handle=" + handle, null);
        return true;
    }

    public static String uProp(String name, String def) {
        record("uniperf", "getProp", "name=" + name + " def=" + def, "", null);
        return def;
    }

    public static int uFeedback(int req, String pkg, int type, int[] args) {
        record("uniperf", "getFeedback", "req=0x" + Integer.toHexString(req) + " type=" + type
                + " args=" + hexArgs(args), "", pkg);
        return -1;
    }

    // ---------------------------------------------------------------- Qualcomm Performance (through PortPerfHook)

    /**
     * args are the original arguments except the Performance instance's mHandle, see PortPerfHook / Performance.java.
     * Returns Integer (int methods), String (perfGetProp etc.) or null (void).
     */
    @Override
    public Object apply(String method, Object[] args) {
        String pkg = null;
        String extra = "";
        StringBuilder b = new StringBuilder();
        if (args != null) {
            for (int i = 0; i < args.length; i++) {
                Object a = args[i];
                if (a instanceof String && ((String) a).startsWith("handle=")) {
                    extra = (String) a;   // handles change every call, keep them out of the summary key
                    continue;
                }
                if (b.length() > 0) b.append(' ');
                if (a instanceof int[]) {
                    b.append(hexArgs((int[]) a));
                } else if (a instanceof Integer && i == 0
                        && !method.startsWith("perfLock") && !method.startsWith("perfIO")) {
                    b.append("0x").append(Integer.toHexString((Integer) a));   // hint / event / request id
                } else if (a instanceof String && pkg == null && !"perfGetProp".equals(method)) {
                    pkg = (String) a;
                    b.append('@');
                } else {
                    b.append(a);
                }
            }
        }
        record("qperf", method, b.toString(), extra, pkg);
        if ("perfGetProp".equals(method)) return args != null && args.length > 1 ? args[1] : null;
        if (method.startsWith("perfSync") || method.startsWith("perfUXEngine_trigger")) return null;
        return FAIL;
    }

    // ---------------------------------------------------------------- logging

    static String hexArgs(int[] a) {
        if (a == null) return "null";
        StringBuilder b = new StringBuilder("[");
        for (int i = 0; i < a.length; i++) {
            if (i > 0) b.append(',');
            // opcodes in hex, values (frequency levels, ms) in decimal: even positions are opcodes
            if ((i & 1) == 0) b.append("0x").append(Integer.toHexString(a[i]));
            else b.append(a[i]);
        }
        return b.append(']').toString();
    }

    /**
     * @param keyPart args that go into the summary key (hint id, duration, opcodes)
     * @param extra   args only for calls.log (handles)
     * @param pkg     package name (calls.log and the summary's last package, not the key)
     */
    static void record(String src, String method, String keyPart, String extra, String pkg) {
        try {
            if (!SystemProperties.getBoolean("persist.sys.port.perf.log", true)) return;
            long now = System.currentTimeMillis();
            String caller = caller();
            String key = src + " " + method + (keyPart.isEmpty() ? "" : " " + keyPart) + " | " + caller;
            String line = src + " " + method + (keyPart.isEmpty() ? "" : " " + keyPart)
                    + (extra.isEmpty() ? "" : " " + extra) + (pkg == null ? "" : " pkg=" + pkg)
                    + " thread=" + Thread.currentThread().getName() + " | " + caller;
            handler().post(new Rec(now, line, key, pkg));
        } catch (Throwable e) {
            Slog.w(TAG, "record failed", e);
        }
    }

    /** First two stack frames outside the performance client itself. */
    static String caller() {
        StackTraceElement[] st = new Throwable().getStackTrace();
        StringBuilder b = new StringBuilder();
        int n = 0;
        for (StackTraceElement e : st) {
            String c = e.getClassName();
            if (c.startsWith("com.android.server.power.PortPerfHint") || c.startsWith("com.qualcomm.qti.")
                    || c.startsWith("com.xiaomi.uniperf.") || c.equals("android.util.BoostFramework")
                    || c.startsWith("java.lang.reflect.") || c.startsWith("jdk.internal.")) {
                continue;
            }
            if (n > 0) b.append(" < ");
            int dot = c.lastIndexOf('.');
            b.append(dot >= 0 ? c.substring(dot + 1) : c).append('.').append(e.getMethodName())
                    .append(':').append(e.getLineNumber());
            if (++n == 2) break;
        }
        return n == 0 ? "?" : b.toString();
    }

    static String time(long t) {
        return new SimpleDateFormat("MM-dd HH:mm:ss.SSS").format(new Date(t));
    }

    /** Runs on the sHandler thread. */
    static void write(long when, String line, String key, String pkg) {
        try {
            Stat s = sStats.get(key);
            if (s == null && sStats.size() < SUM_MAX_KEYS) {
                s = new Stat();
                s.first = when;
                sStats.put(key, s);
            }
            if (s != null) {
                s.count++;
                s.last = when;
                if (pkg != null) s.lastPkg = pkg;
            }
            if (!sSumPending) {
                sSumPending = true;
                sHandler.postDelayed(WRITE_SUMMARY, SUM_DELAY);
            }
            File f = new File(LOG);
            if (f.length() > LOG_MAX) f.renameTo(new File(LOG + ".old"));
            FileOutputStream o = new FileOutputStream(f, true);
            try {
                o.write((time(when) + " " + line + "\n").getBytes());
            } finally {
                o.close();
            }
        } catch (Throwable e) {
            Slog.w(TAG, "write failed", e);
        }
    }

    static void summary() {
        sSumPending = false;
        try {
            ArrayList<Map.Entry<String, Stat>> l = new ArrayList<>(sStats.entrySet());
            Collections.sort(l, (a, b) -> Long.compare(b.getValue().count, a.getValue().count));
            StringBuilder b = new StringBuilder();
            b.append("# boot ").append(time(sBoot)).append("  written ").append(time(System.currentTimeMillis()))
                    .append("  keys ").append(l.size()).append(l.size() >= SUM_MAX_KEYS ? " (full)" : "")
                    .append('\n');
            b.append("# count\tfirst\tlast\tkey\tlast pkg\n");
            for (Map.Entry<String, Stat> e : l) {
                Stat s = e.getValue();
                b.append(s.count).append('\t').append(time(s.first)).append('\t').append(time(s.last))
                        .append('\t').append(e.getKey()).append('\t').append(s.lastPkg == null ? "-" : s.lastPkg)
                        .append('\n');
            }
            File tmp = new File(SUM + ".tmp");
            FileOutputStream o = new FileOutputStream(tmp);
            try {
                o.write(b.toString().getBytes());
            } finally {
                o.close();
            }
            tmp.renameTo(new File(SUM));
        } catch (Throwable e) {
            Slog.w(TAG, "summary failed", e);
        }
    }
}
