/*
 * Added to QPerformance.jar (boot classpath). Performance perf* methods call here (see Performance.java).
 * In system_server PortPerfBridge.start() -> PortPerfHint.start() sets sHook and calls are logged there;
 * in other processes sHook is null and calls fail without looking up perf2 / perfservice.
 * build.sh marks the members whitelist for hiddenapi.
 */
package com.qualcomm.qti;

import java.util.function.BiFunction;

public final class PortPerfHook {
    public static volatile BiFunction<String, Object[], Object> sHook;

    private PortPerfHook() {}

    static Object call(String m, Object[] a) {
        BiFunction<String, Object[], Object> h = sHook;
        if (h == null) return null;
        try {
            return h.apply(m, a);
        } catch (Throwable e) {
            return null;
        }
    }

    static int i(String m, Object... a) {
        Object r = sHook == null ? null : call(m, a);
        return r instanceof Integer ? (Integer) r : -1;
    }

    static void v(String m, Object... a) {
        if (sHook != null) call(m, a);
    }

    static String s(String m, String def, Object... a) {
        Object r = sHook == null ? def : call(m, a);
        return r instanceof String ? (String) r : def;
    }
}
