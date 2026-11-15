/*
 * Stand-in for Xiaomi's touch HAL (vendor.xiaomi.hw.touchfeature.ITouchFeature/default, AIDL) on the Pixel 6a.
 * Runs in system_server; start() is called at the beginning of SystemServerImpl.addExtraServices.
 *
 * There is no system service in between on Xiaomi: miui.util.ITouchFeature in miui-framework, TouchService.apk,
 * PowerKeeper and SurfaceFlinger's libtouchflinger / libtouchfeatureutils / libtouchscheduler look up the HAL by name.
 * This registers a service with that name and handles transactions by number, following miui.util.ITouchFeature:
 *   1 getModeCurValue(touchId, mode) -> int        2 default   3 max   4 min (same args and result as 1)
 *   5 getModeValues(touchId, mode) -> int[4]        client preallocates 4; {cur, default, min, max} as Xiaomi's driver
 *   6 getTouchEvent() -> String
 *   7 modeReset(touchId, mode) -> int (0 = ok)
 *   8 setModeLongValue(touchId, mode, length, int[] values) -> int   (client setEdgeMode)
 *   9 setModeValue(touchId, mode, value) -> int (0 = ok; otherwise the client logs "failed. ret = ")
 *  10 getModeCurValueString(touchId, mode) -> String
 *  11 getModeWhiteList(touchId, int[]) -> String
 *  12 registerCallback(touchId, ITouchFeatureCallback, clientName)   13 unregisterCallback (same args)
 *  14 setModePackageName(touchId, mode, packageName)
 *  0xfffffe / 0xfffffd: AIDL getInterfaceVersion / getInterfaceHash (hash from libtouchflinger).
 * 12-14 only read the exception in Java; NDK clients may read an int result, so a 0 is always appended.
 *
 * Values are stored and read back without touching hardware. Unsupported modes report max = min = 0 so no slider shows.
 *   Sets, resets, registrations and the first read of each (transaction, display, mode, process) are logged to
 *   /data/system/port_touch/calls.log (rotated to .old at 1 MB) and logcat. dumpsys on the service shows the table.
 * Touch context to the Pixel twoshay (PortTouchContext.java): rotation is tracked directly; glove (40) ->
 *   screenProtectorMode ("increase touch sensitivity"). Orientation (mode 8) from Xiaomi is only logged.
 * persist.sys.port.touch.enable=0: not registered; persist.sys.port.touch.twoshay=0: no context (system_server restart).
 * Every entry point catches Throwable; exceptions in onTransact are written back to the client as usual.
 */
package com.android.server.input;

import android.content.Context;
import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;
import android.os.RemoteException;
import android.os.ServiceManager;
import android.os.SystemProperties;
import android.util.Slog;

import java.io.File;
import java.io.FileDescriptor;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.TreeMap;

public final class PortTouchFeature extends Binder {
    static final String TAG = "PortTouchFeature";
    static final String NAME = "vendor.xiaomi.hw.touchfeature.ITouchFeature/default";
    static final String DESC = "vendor.xiaomi.hw.touchfeature.ITouchFeature";
    static final String DIR = "/data/system/port_touch";
    static final String LOG = DIR + "/calls.log";

    static final int VERSION = 1;
    static final String HASH = "734e11ac1aabda7e8d55c6a8d162630186d35915";
    static final int TX_GET_VERSION = 0x00fffffe;
    static final int TX_GET_HASH = 0x00fffffd;

    static final int CUR = 0, DEF = 1, MIN = 2, MAX = 3;
    static final int MODE_GLOVE = 40;

    static PortTouchFeature sInstance;

    /** (touchId, mode) -> {cur, default, min, max}. Modes never set are all 0. */
    final TreeMap<Long, int[]> mModes = new TreeMap<>();
    /** Arrays from setModeLongValue (edge areas etc.), stored as is. */
    final TreeMap<Long, int[]> mLong = new TreeMap<>();
    /** Package name from setModePackageName. */
    final TreeMap<Long, String> mPkg = new TreeMap<>();
    /** Registered callbacks: client name -> binder. Never called back. */
    final HashMap<String, IBinder> mCallbacks = new HashMap<>();
    /** Reads are only logged the first time. */
    final HashSet<String> mSeen = new HashSet<>();
    final HashMap<Integer, Integer> mCount = new HashMap<>();

    public static void start(Context context) {
        try {
            synchronized (PortTouchFeature.class) {
                if (sInstance != null) return;
                if (!SystemProperties.getBoolean("persist.sys.port.touch.enable", true)) {
                    Slog.i(TAG, "disabled by persist.sys.port.touch.enable");
                    return;
                }
                PortTouchFeature s = new PortTouchFeature();
                ServiceManager.addService(NAME, s);
                sInstance = s;
            }
            record("start: registered " + NAME);
        } catch (Throwable e) {
            Slog.w(TAG, "start failed", e);
            record("start failed: " + e);
        }
        PortTouchContext.start(context);
    }

    PortTouchFeature() {
        attachInterface(null, DESC);
    }

    static long key(int touchId, int mode) {
        return ((long) touchId << 32) | (mode & 0xffffffffL);
    }

    int[] entry(int touchId, int mode) {
        int[] v = mModes.get(key(touchId, mode));
        if (v == null) {
            v = new int[4];
            mModes.put(key(touchId, mode), v);
        }
        return v;
    }

    int[] peek(int touchId, int mode) {
        int[] v = mModes.get(key(touchId, mode));
        return v == null ? new int[4] : v;
    }

    @Override
    protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
        if ((code < 1 || code > 14) && code != TX_GET_VERSION && code != TX_GET_HASH) {
            return super.onTransact(code, data, reply, flags);
        }
        data.enforceInterface(DESC);
        synchronized (this) {
            Integer n = mCount.get(code);
            mCount.put(code, n == null ? 1 : n + 1);
        }
        int id, mode;
        switch (code) {
            case 1: case 2: case 3: case 4: {
                id = data.readInt();
                mode = data.readInt();
                int r;
                synchronized (this) {
                    r = peek(id, mode)[code == 1 ? CUR : code == 2 ? DEF : code == 3 ? MAX : MIN];
                }
                once(code, id, mode, "get" + new String[] {"", "Cur", "Def", "Max", "Min"}[code]
                        + " touch=" + id + " mode=" + mode + " -> " + r);
                reply.writeNoException();
                reply.writeInt(r);
                return true;
            }
            case 5: {
                id = data.readInt();
                mode = data.readInt();
                int[] r;
                synchronized (this) {
                    r = peek(id, mode).clone();
                }
                once(code, id, mode, "getModeValues touch=" + id + " mode=" + mode + " -> " + Arrays.toString(r));
                reply.writeNoException();
                reply.writeIntArray(r);
                return true;
            }
            case 6:
                once(code, 0, 0, "getTouchEvent");
                reply.writeNoException();
                reply.writeString("");
                return true;
            case 7: {
                id = data.readInt();
                mode = data.readInt();
                synchronized (this) {
                    int[] v = entry(id, mode);
                    v[CUR] = v[DEF];
                }
                record("modeReset touch=" + id + " mode=" + mode);
                reply.writeNoException();
                reply.writeInt(0);
                return true;
            }
            case 8: {
                id = data.readInt();
                mode = data.readInt();
                int len = data.readInt();
                int[] vals = data.createIntArray();
                synchronized (this) {
                    mLong.put(key(id, mode), vals);
                }
                record("setModeLongValue touch=" + id + " mode=" + mode + " len=" + len
                        + " values=" + Arrays.toString(vals));
                reply.writeNoException();
                reply.writeInt(0);
                return true;
            }
            case 9: {
                id = data.readInt();
                mode = data.readInt();
                int value = data.readInt();
                int old;
                synchronized (this) {
                    int[] v = entry(id, mode);
                    old = v[CUR];
                    v[CUR] = value;
                }
                record("setModeValue touch=" + id + " mode=" + mode + " value=" + value + " (was " + old + ")");
                if (id == 0 && mode == MODE_GLOVE) PortTouchContext.setScreenProtector(value != 0);
                reply.writeNoException();
                reply.writeInt(0);
                return true;
            }
            case 10:
                id = data.readInt();
                mode = data.readInt();
                once(code, id, mode, "getModeCurValueString touch=" + id + " mode=" + mode);
                reply.writeNoException();
                reply.writeString("");
                return true;
            case 11: {
                id = data.readInt();
                int[] arg = data.createIntArray();
                once(code, id, 0, "getModeWhiteList touch=" + id + " arg=" + Arrays.toString(arg));
                reply.writeNoException();
                reply.writeString("");
                return true;
            }
            case 12: case 13: {
                id = data.readInt();
                IBinder cb = data.readStrongBinder();
                String client = data.readString();
                synchronized (this) {
                    if (code == 12) mCallbacks.put(id + ":" + client, cb);
                    else mCallbacks.remove(id + ":" + client);
                }
                record((code == 12 ? "registerCallback" : "unregisterCallback") + " touch=" + id
                        + " client=" + client + " binder=" + (cb == null ? "null" : "ok"));
                reply.writeNoException();
                reply.writeInt(0);
                return true;
            }
            case 14: {
                id = data.readInt();
                mode = data.readInt();
                String pkg = data.readString();
                synchronized (this) {
                    mPkg.put(key(id, mode), pkg);
                }
                record("setModePackageName touch=" + id + " mode=" + mode + " pkg=" + pkg);
                reply.writeNoException();
                reply.writeInt(0);
                return true;
            }
            case TX_GET_VERSION:
                once(code, 0, 0, "getInterfaceVersion");
                reply.writeNoException();
                reply.writeInt(VERSION);
                return true;
            case TX_GET_HASH:
                once(code, 0, 0, "getInterfaceHash");
                reply.writeNoException();
                reply.writeString(HASH);
                return true;
        }
        return false;
    }

    void once(int code, int id, int mode, String what) {
        String k = code + "/" + id + "/" + mode + "/" + Binder.getCallingPid();
        synchronized (this) {
            if (mSeen.size() > 4000 || !mSeen.add(k)) return;
        }
        record(what + " (first)");
    }

    static String caller() {
        int pid = Binder.getCallingPid();
        String name = "?";
        try {
            FileInputStream in = new FileInputStream("/proc/" + pid + "/cmdline");
            try {
                byte[] b = new byte[128];
                int n = in.read(b);
                int e = 0;
                while (e < n && b[e] != 0) e++;
                if (e > 0) name = new String(b, 0, e);
            } finally {
                in.close();
            }
        } catch (Throwable ignored) {
        }
        return "uid=" + Binder.getCallingUid() + " pid=" + pid + " proc=" + name;
    }

    static void record(String what) {
        try {
            String line = System.currentTimeMillis() + " " + what + " " + caller();
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

    @Override
    protected void dump(FileDescriptor fd, PrintWriter pw, String[] args) {
        synchronized (this) {
            pw.println("PortTouchFeature (" + NAME + ")");
            pw.println("modes (touch/mode: cur def min max):");
            for (Map.Entry<Long, int[]> e : mModes.entrySet()) {
                long k = e.getKey();
                pw.println("  " + (k >> 32) + "/" + (int) k + ": " + Arrays.toString(e.getValue()));
            }
            pw.println("long values:");
            for (Map.Entry<Long, int[]> e : mLong.entrySet()) {
                long k = e.getKey();
                pw.println("  " + (k >> 32) + "/" + (int) k + ": " + Arrays.toString(e.getValue()));
            }
            pw.println("package names:");
            for (Map.Entry<Long, String> e : mPkg.entrySet()) {
                long k = e.getKey();
                pw.println("  " + (k >> 32) + "/" + (int) k + ": " + e.getValue());
            }
            pw.println("callbacks: " + mCallbacks.keySet());
            pw.println("transaction counts: " + mCount);
        }
    }
}
