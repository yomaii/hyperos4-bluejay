/*
 * Not a complete class: only the method bodies that replace those in com.xiaomi.uniperf.UniperfClient
 * (miui-services.jar), merged with the original method headers by build.sh.
 * Signatures must match the original class.
 *
 * getUniperfservice() returns true so Xiaomi's policies (PerfBoostPolicy, ThirdPartyFreqController) keep running;
 * other calls are logged by PortPerfHint and not executed. No IUniperf lookup.
 * Unchanged: <clinit>, <init>, onBinderUnAvailable, UniperfJCLog (they do not touch the service).
 */
package com.xiaomi.uniperf;

import com.android.server.power.PortPerfHint;

public class UniperfClient {
    public static boolean getUniperfservice() {
        return true;
    }

    public long UniperfHint(long handleId, int hintId, int hintType, int duration, String userData) {
        return PortPerfHint.uHint(handleId, hintId, hintType, duration, userData);
    }

    public long UniperfLockAcquire(long handleId, int duration, int... list) {
        return PortPerfHint.uLock("lockAcquire", handleId, duration, list);
    }

    public boolean UniperfRelease(long handleId) {
        return PortPerfHint.uRelease(handleId);
    }

    public long UniperfSetFreqlevel(long handleId, int duration, int... list) {
        return PortPerfHint.uLock("setFreqlevel", handleId, duration, list);
    }

    public int perfGetFeedback(int req, String pkg) {
        return PortPerfHint.uFeedback(req, pkg, 0, new int[0]);
    }

    public int perfGetFeedbackExtn(int req, String pkg, int type, int... list) {
        return PortPerfHint.uFeedback(req, pkg, type, list);
    }

    public String perfGetProp(String name, String def) {
        return PortPerfHint.uProp(name, def);
    }
}
