/*
 * Not a complete class: only the method bodies that replace those in com.qualcomm.qti.Performance (QPerformance.jar).
 * build.sh takes these methods and gives them the original method headers (merge_methods.py).
 * Signatures must match the original class.
 *
 * Everything goes to PortPerfHook: logged in system_server, returns right away elsewhere. Return values match a
 * missing perf HAL (-1). Arguments are passed hint first so PortPerfHint can log them in hex.
 * connectPerfServiceLocked() does nothing: no vendor.perfservice lookup.
 */
package com.qualcomm.qti;

public class Performance {
    private void connectPerfServiceLocked() {
    }

    public void perfEvent(int eventId, String pkg, int numArgs, int... list) {
        PortPerfHook.v("perfEvent", eventId, pkg, numArgs, list);
    }

    public int perfGetFeedback(int req, String pkg) {
        return PortPerfHook.i("perfGetFeedback", req, pkg);
    }

    public int perfGetFeedbackExtn(int req, String pkg, int numArgs, int... list) {
        return PortPerfHook.i("perfGetFeedbackExtn", req, pkg, numArgs, list);
    }

    public double perfGetHalVer() {
        PortPerfHook.v("perfGetHalVer");
        return 2.2;   // DEF_PERF_HAL of the original class
    }

    public String perfGetProp(String name, String def) {
        return PortPerfHook.s("perfGetProp", def, name, def);
    }

    public int perfHint(int hint, String pkg, int duration, int type) {
        return PortPerfHook.i("perfHint", hint, pkg, duration, type);
    }

    public int perfHintAcqRel(int handle, int hint, String pkg, int duration, int type, int numArgs, int... list) {
        return PortPerfHook.i("perfHintAcqRel", hint, pkg, duration, type, list, "handle=" + handle);
    }

    public void perfHintAsync(int handle, int hint, String pkg, int duration, int type, int numArgs, int... list) {
        PortPerfHook.v("perfHintAsync", hint, pkg, duration, type, list, "handle=" + handle);
    }

    public int perfHintRelease() {
        return PortPerfHook.i("perfHintRelease");
    }

    public int perfHintRenew(int handle, int hint, String pkg, int duration, int type, int numArgs, int... list) {
        return PortPerfHook.i("perfHintRenew", hint, pkg, duration, type, list, "handle=" + handle);
    }

    public int perfIOPrefetchStart(int pid, String pkg, String codePath) {
        return PortPerfHook.i("perfIOPrefetchStart", pid, pkg, codePath);
    }

    public int perfIOPrefetchStop() {
        return PortPerfHook.i("perfIOPrefetchStop");
    }

    public int perfLockAcqAndRelease(int handle, int duration, int numArgs, int reserveNumArgs, int... list) {
        return PortPerfHook.i("perfLockAcqAndRelease", duration, list, "handle=" + handle);
    }

    public int perfLockAcquire(int duration, int... list) {
        return PortPerfHook.i("perfLockAcquire", duration, list);
    }

    public int perfLockRelease() {
        return PortPerfHook.i("perfLockRelease");
    }

    public int perfLockReleaseHandler(int handle) {
        return PortPerfHook.i("perfLockReleaseHandler", "handle=" + handle);
    }

    public String perfSyncRequest(int cmd) {
        return PortPerfHook.s("perfSyncRequest", null, cmd);
    }

    public int perfUXEngine_events(int opcode, int pid, String pkg, int lat, String id) {
        return PortPerfHook.i("perfUXEngine_events", opcode, pkg, pid, lat, id);
    }

    public String perfUXEngine_trigger(int opcode) {
        return PortPerfHook.s("perfUXEngine_trigger", null, opcode);
    }
}
