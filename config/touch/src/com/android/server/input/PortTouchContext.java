/*
 * Sends touch context to the Pixel 6a twoshay (vendor touch processing: grip / palm rejection).
 *
 * On a Pixel, SystemUIGoogle's TouchContextService sends it; HyperOS has none, so twoshay never gets context
 * (grip rejection assumes portrait in landscape). Sent from system_server, same format as the stock client:
 *   service com.google.input.ITouchContextService/default, transaction 1 updateContext(ContextPacket), oneway.
 *   ContextPacket (stable AIDL parcelable, size-prefixed):
 *     byte orientation              DisplayInfo.rotation (0-3) of the default display
 *     byte audioMode                always 0 (normal)
 *     byte adaptiveTouchSensitivity -1 = unset
 *     byte screenProtectorMode      Settings.Secure touch_sensitivity_enabled; -1 = unset
 *     ImeState imeState             {displayId, visible, top, left, bottom, right}; always default display, hidden, zeros
 *     byte audioDeviceInfo          0
 *   Java writeByte writes 4 bytes and NDK reads a byte as 4 bytes, so they match.
 * Screen protector mode follows Xiaomi's glove mode (mode 40 from the Settings switch via TouchWakeUpFeatureManager).
 *
 * Runs on the PortTouchFeature thread: sends on rotation (DisplayListener) and glove changes; reconnects and resends
 * after twoshay restarts. Retries every 10 s, up to 60 times, while unavailable. Every entry point catches Throwable.
 */
package com.android.server.input;

import android.content.Context;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Message;
import android.os.Parcel;
import android.os.ServiceManager;
import android.os.SystemProperties;
import android.util.Slog;
import android.view.Display;

final class PortTouchContext extends Handler implements DisplayManager.DisplayListener, IBinder.DeathRecipient {
    static final String TAG = "PortTouchContext";
    static final String SVC = "com.google.input.ITouchContextService/default";
    static final String DESC = "com.google.input.ITouchContextService";
    static final int TX_UPDATE_CONTEXT = 1;

    static final int MSG_SYNC = 1;        // connect if needed and send
    static final int MSG_PROTECTOR = 2;   // arg1 = 0/1

    static PortTouchContext sInstance;
    /** Glove state received before the service was up (-1 = none). */
    static int sPendingProtector = -1;

    final Context mContext;
    DisplayManager mDm;
    IBinder mRemote;
    int mRetries;
    int mOrientation = -1;
    int mProtector = -1;
    String mLastSent;

    static void start(Context context) {
        try {
            if (!SystemProperties.getBoolean("persist.sys.port.touch.twoshay", true)) {
                PortTouchFeature.record("twoshay: disabled by persist.sys.port.touch.twoshay");
                return;
            }
            synchronized (PortTouchContext.class) {
                if (sInstance != null) return;
                HandlerThread t = new HandlerThread(TAG);
                t.start();
                sInstance = new PortTouchContext(context, t);
                if (sPendingProtector >= 0) sInstance.mProtector = sPendingProtector;
            }
            sInstance.sendEmptyMessage(MSG_SYNC);
        } catch (Throwable e) {
            Slog.w(TAG, "start failed", e);
        }
    }

    static void setScreenProtector(boolean on) {
        synchronized (PortTouchContext.class) {
            if (sInstance == null) {
                sPendingProtector = on ? 1 : 0;
                return;
            }
            sInstance.obtainMessage(MSG_PROTECTOR, on ? 1 : 0, 0).sendToTarget();
        }
    }

    PortTouchContext(Context context, HandlerThread t) {
        super(t.getLooper());
        mContext = context;
    }

    @Override
    public void handleMessage(Message msg) {
        try {
            if (msg.what == MSG_PROTECTOR) {
                if (mProtector == msg.arg1) return;
                mProtector = msg.arg1;
            }
            sync();
        } catch (Throwable e) {
            Slog.w(TAG, "handle failed", e);
            retry();
        }
    }

    void retry() {
        if (mRetries++ < 60 && !hasMessages(MSG_SYNC)) sendEmptyMessageDelayed(MSG_SYNC, 10000);
    }

    void sync() throws Exception {
        if (mDm == null) {
            DisplayManager dm = mContext.getSystemService(DisplayManager.class);
            if (dm == null) {
                retry();
                return;
            }
            dm.registerDisplayListener(this, this);
            mDm = dm;
        }
        Display d = mDm.getDisplay(Display.DEFAULT_DISPLAY);
        if (d != null) mOrientation = d.getRotation();
        if (mRemote == null) {
            IBinder b = ServiceManager.getService(SVC);
            if (b == null) {
                PortTouchFeature.record("twoshay: " + SVC + " not found (retry " + mRetries + ")");
                retry();
                return;
            }
            b.linkToDeath(this, 0);
            mRemote = b;
            mLastSent = null;
            PortTouchFeature.record("twoshay: connected");
        }
        send();
    }

    void send() throws Exception {
        int orientation = mOrientation < 0 ? 0 : mOrientation;
        String what = "orientation=" + orientation + " screenProtector=" + mProtector;
        if (what.equals(mLastSent)) return;
        Parcel p = Parcel.obtain();
        try {
            p.writeInterfaceToken(DESC);
            p.writeInt(1);                       // non-null
            int start = p.dataPosition();
            p.writeInt(0);                       // size, filled in at the end
            p.writeByte((byte) orientation);
            p.writeByte((byte) 0);               // audioMode
            p.writeByte((byte) -1);              // adaptiveTouchSensitivity: unset
            p.writeByte((byte) mProtector);      // screenProtectorMode
            p.writeInt(1);                       // imeState non-null
            int ime = p.dataPosition();
            p.writeInt(0);
            p.writeInt(Display.DEFAULT_DISPLAY);
            p.writeBoolean(false);
            p.writeInt(0);
            p.writeInt(0);
            p.writeInt(0);
            p.writeInt(0);
            patch(p, ime);
            p.writeByte((byte) 0);               // audioDeviceInfo
            patch(p, start);
            mRemote.transact(TX_UPDATE_CONTEXT, p, null, IBinder.FLAG_ONEWAY);
        } finally {
            p.recycle();
        }
        mLastSent = what;
        PortTouchFeature.record("twoshay: updateContext " + what);
    }

    static void patch(Parcel p, int start) {
        int end = p.dataPosition();
        p.setDataPosition(start);
        p.writeInt(end - start);
        p.setDataPosition(end);
    }

    @Override
    public void onDisplayChanged(int displayId) {
        if (displayId != Display.DEFAULT_DISPLAY) return;
        try {
            Display d = mDm.getDisplay(Display.DEFAULT_DISPLAY);
            if (d == null || d.getRotation() == mOrientation) return;
            mOrientation = d.getRotation();
            if (mRemote != null) send();
        } catch (Throwable e) {
            Slog.w(TAG, "onDisplayChanged failed", e);
        }
    }

    @Override
    public void onDisplayAdded(int displayId) {
    }

    @Override
    public void onDisplayRemoved(int displayId) {
    }

    @Override
    public void binderDied() {
        PortTouchFeature.record("twoshay: died, reconnecting");
        post(new Runnable() {
            public void run() {
                mRemote = null;
                mRetries = 0;
                sendEmptyMessageDelayed(MSG_SYNC, 1000);
            }
        });
    }
}
