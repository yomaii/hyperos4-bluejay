.class public final Lcom/android/server/port/PortGestures;
.super Landroid/content/BroadcastReceiver;
.source "PortGestures.java"

# interfaces
.implements Landroid/os/Handler$Callback;

# Double-tap to wake and AOD long press on the fingerprint area. Runs in system_server.
#
# Xiaomi does these in the touch driver + touchfeature HAL. The Pixel 6a has two wake-up one-shot sensors
# (low-power touch scanning reported by the sensor HAL):
#   com.google.sensor.single_touch  tap with the screen off (no double-tap sensor on the 6a)
#   com.google.sensor.long_press    long press on the fingerprint area
# Registered on SCREEN_OFF, unregistered on SCREEN_ON:
#   tap: wake on a second tap within 600 ms (re-registered after each event); any tap with Global port_tap_wake=1.
#        Not registered when System gesture_wakeup=0.
#   long press: wake; poll the display state every 50 ms (up to 2 s) and 150 ms after ON inject a 900 ms press
#        at the sensor center (540,1715) so SystemUI's UdfpsController runs the normal keyguard flow.
# Every entry point catches exceptions and only logs (tag PortGestures).
# start() is called from fp_setUdfpsOverlayController.smali.


# static fields
.field private static sInstance:Lcom/android/server/port/PortGestures;


# instance fields
.field private final mContext:Landroid/content/Context;

.field private mDownTime:J

.field private final mHandler:Landroid/os/Handler;

.field private mLastTap:J

.field private mPendingFp:Z

.field private mPoll:I

.field private final mPressListener:Lcom/android/server/port/PortGestures$L;

.field private mPressSensor:Landroid/hardware/Sensor;

.field private mSensorManager:Landroid/hardware/SensorManager;

.field private final mTapListener:Lcom/android/server/port/PortGestures$L;

.field private mTapSensor:Landroid/hardware/Sensor;


# direct methods
.method private constructor <init>(Landroid/content/Context;)V
    .registers 5

    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V

    iput-object p1, p0, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    new-instance v0, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v1

    invoke-direct {v0, v1, p0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;Landroid/os/Handler$Callback;)V

    iput-object v0, p0, Lcom/android/server/port/PortGestures;->mHandler:Landroid/os/Handler;

    new-instance v0, Lcom/android/server/port/PortGestures$L;

    const/4 v1, 0x1

    invoke-direct {v0, p0, v1}, Lcom/android/server/port/PortGestures$L;-><init>(Lcom/android/server/port/PortGestures;I)V

    iput-object v0, p0, Lcom/android/server/port/PortGestures;->mTapListener:Lcom/android/server/port/PortGestures$L;

    new-instance v0, Lcom/android/server/port/PortGestures$L;

    const/4 v1, 0x2

    invoke-direct {v0, p0, v1}, Lcom/android/server/port/PortGestures$L;-><init>(Lcom/android/server/port/PortGestures;I)V

    iput-object v0, p0, Lcom/android/server/port/PortGestures;->mPressListener:Lcom/android/server/port/PortGestures$L;

    return-void
.end method

.method public static start(Landroid/content/Context;)V
    .registers 4

    :try_start_0
    sget-object v0, Lcom/android/server/port/PortGestures;->sInstance:Lcom/android/server/port/PortGestures;

    if-nez v0, :cond_2c

    new-instance v0, Lcom/android/server/port/PortGestures;

    invoke-direct {v0, p0}, Lcom/android/server/port/PortGestures;-><init>(Landroid/content/Context;)V

    sput-object v0, Lcom/android/server/port/PortGestures;->sInstance:Lcom/android/server/port/PortGestures;

    new-instance v1, Landroid/content/IntentFilter;

    invoke-direct {v1}, Landroid/content/IntentFilter;-><init>()V

    const-string v2, "android.intent.action.SCREEN_OFF"

    invoke-virtual {v1, v2}, Landroid/content/IntentFilter;->addAction(Ljava/lang/String;)V

    const-string v2, "android.intent.action.SCREEN_ON"

    invoke-virtual {v1, v2}, Landroid/content/IntentFilter;->addAction(Ljava/lang/String;)V

    invoke-virtual {p0, v0, v1}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;

    const-string v0, "PortGestures"

    const-string v1, "started"

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    :try_end_2c
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_2c} :catch_2d

    :cond_2c
    return-void

    :catch_2d
    move-exception v0

    const-string v1, "PortGestures"

    const-string v2, "start failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method

.method private ensureSensors()V
    .registers 5

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mSensorManager:Landroid/hardware/SensorManager;

    if-nez v0, :cond_50

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    const-string v1, "sensor"

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/hardware/SensorManager;

    iput-object v0, p0, Lcom/android/server/port/PortGestures;->mSensorManager:Landroid/hardware/SensorManager;

    const/4 v1, -0x1

    invoke-virtual {v0, v1}, Landroid/hardware/SensorManager;->getSensorList(I)Ljava/util/List;

    move-result-object v0

    invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;

    move-result-object v0

    :goto_1e
    invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z

    move-result v1

    if-eqz v1, :cond_50

    invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Landroid/hardware/Sensor;

    invoke-virtual {v1}, Landroid/hardware/Sensor;->getStringType()Ljava/lang/String;

    move-result-object v2

    const-string v3, "com.google.sensor.single_touch"

    invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v3

    if-eqz v3, :cond_40

    iput-object v1, p0, Lcom/android/server/port/PortGestures;->mTapSensor:Landroid/hardware/Sensor;

    goto :goto_1e

    :cond_40
    const-string v3, "com.google.sensor.long_press"

    invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v3

    if-eqz v3, :goto_1e

    iput-object v1, p0, Lcom/android/server/port/PortGestures;->mPressSensor:Landroid/hardware/Sensor;

    goto :goto_1e

    :cond_50
    return-void
.end method

.method private arm()V
    .registers 6

    invoke-direct {p0}, Lcom/android/server/port/PortGestures;->ensureSensors()V

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mSensorManager:Landroid/hardware/SensorManager;

    iget-object v1, p0, Lcom/android/server/port/PortGestures;->mTapSensor:Landroid/hardware/Sensor;

    if-eqz v1, :cond_24

    iget-object v2, p0, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    invoke-virtual {v2}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v2

    const-string v3, "gesture_wakeup"

    const/4 v4, 0x1

    invoke-static {v2, v3, v4}, Landroid/provider/Settings$System;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I

    move-result v2

    if-eqz v2, :cond_24

    iget-object v2, p0, Lcom/android/server/port/PortGestures;->mTapListener:Lcom/android/server/port/PortGestures$L;

    invoke-virtual {v0, v2, v1}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    # Long press is handled in SystemUI (PortAodLongPress) unless Global port_udfps_mode=1
    :cond_24
    iget-object v2, p0, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    invoke-virtual {v2}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v2

    const-string v3, "port_udfps_mode"

    const/4 v4, 0x0

    invoke-static {v2, v3, v4}, Landroid/provider/Settings$Global;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I

    move-result v2

    const/4 v3, 0x1

    if-ne v2, v3, :cond_30

    iget-object v1, p0, Lcom/android/server/port/PortGestures;->mPressSensor:Landroid/hardware/Sensor;

    if-eqz v1, :cond_30

    iget-object v2, p0, Lcom/android/server/port/PortGestures;->mPressListener:Lcom/android/server/port/PortGestures$L;

    invoke-virtual {v0, v2, v1}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    :cond_30
    return-void
.end method

.method private disarm()V
    .registers 4

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mSensorManager:Landroid/hardware/SensorManager;

    if-eqz v0, :cond_20

    iget-object v1, p0, Lcom/android/server/port/PortGestures;->mTapSensor:Landroid/hardware/Sensor;

    if-eqz v1, :cond_12

    iget-object v2, p0, Lcom/android/server/port/PortGestures;->mTapListener:Lcom/android/server/port/PortGestures$L;

    invoke-virtual {v0, v2, v1}, Landroid/hardware/SensorManager;->cancelTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    :cond_12
    iget-object v1, p0, Lcom/android/server/port/PortGestures;->mPressSensor:Landroid/hardware/Sensor;

    if-eqz v1, :cond_20

    iget-object v2, p0, Lcom/android/server/port/PortGestures;->mPressListener:Lcom/android/server/port/PortGestures$L;

    invoke-virtual {v0, v2, v1}, Landroid/hardware/SensorManager;->cancelTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    :cond_20
    return-void
.end method

# inject(downTime, eventTime, action): touch event at the fingerprint area center
.method private inject(JJI)V
    .registers 28

    # Needs a touch area: UdfpsController checks how much of the sensor the touch ellipse covers, and a zero-size
    # event never reaches onPointerDown. A real finger is about 143x106; use 200x200.
    new-instance v0, Landroid/view/MotionEvent$PointerProperties;

    invoke-direct {v0}, Landroid/view/MotionEvent$PointerProperties;-><init>()V

    const/4 v1, 0x0

    iput v1, v0, Landroid/view/MotionEvent$PointerProperties;->id:I

    # MotionEvent.TOOL_TYPE_FINGER
    const/4 v1, 0x1

    iput v1, v0, Landroid/view/MotionEvent$PointerProperties;->toolType:I

    new-array v2, v1, [Landroid/view/MotionEvent$PointerProperties;

    const/4 v3, 0x0

    aput-object v0, v2, v3

    new-instance v0, Landroid/view/MotionEvent$PointerCoords;

    invoke-direct {v0}, Landroid/view/MotionEvent$PointerCoords;-><init>()V

    # 540.0f, 1715.0f: center of udfpsBounds Rect(425,1600 - 655,1830)
    const v4, 0x44070000

    iput v4, v0, Landroid/view/MotionEvent$PointerCoords;->x:F

    const v4, 0x44d66000

    iput v4, v0, Landroid/view/MotionEvent$PointerCoords;->y:F

    # pressure 1.0f
    const/high16 v4, 0x3f800000

    iput v4, v0, Landroid/view/MotionEvent$PointerCoords;->pressure:F

    # size 0.125f
    const/high16 v4, 0x3e000000

    iput v4, v0, Landroid/view/MotionEvent$PointerCoords;->size:F

    # 200.0f
    const/high16 v4, 0x43480000

    iput v4, v0, Landroid/view/MotionEvent$PointerCoords;->touchMajor:F

    iput v4, v0, Landroid/view/MotionEvent$PointerCoords;->touchMinor:F

    iput v4, v0, Landroid/view/MotionEvent$PointerCoords;->toolMajor:F

    iput v4, v0, Landroid/view/MotionEvent$PointerCoords;->toolMinor:F

    new-array v5, v1, [Landroid/view/MotionEvent$PointerCoords;

    aput-object v0, v5, v3

    # obtain(downTime, eventTime, action, pointerCount, props, coords, metaState, buttonState,
    #        xPrecision, yPrecision, deviceId, edgeFlags, source, flags)
    move-wide/from16 v6, p1

    move-wide/from16 v8, p3

    move/from16 v10, p5

    const/4 v11, 0x1

    move-object v12, v2

    move-object v13, v5

    const/4 v14, 0x0

    const/4 v15, 0x0

    const/high16 v16, 0x3f800000

    const/high16 v17, 0x3f800000

    const/16 v18, 0x0

    const/16 v19, 0x0

    # InputDevice.SOURCE_TOUCHSCREEN
    const/16 v20, 0x1002

    const/16 v21, 0x0

    invoke-static/range {v6 .. v21}, Landroid/view/MotionEvent;->obtain(JJII[Landroid/view/MotionEvent$PointerProperties;[Landroid/view/MotionEvent$PointerCoords;IIFFIIII)Landroid/view/MotionEvent;

    move-result-object v0

    move-object/from16 v1, p0

    iget-object v1, v1, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    const-string v2, "input"

    invoke-virtual {v1, v2}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Landroid/hardware/input/InputManager;

    # INJECT_INPUT_EVENT_MODE_ASYNC
    const/4 v2, 0x0

    invoke-virtual {v1, v0, v2}, Landroid/hardware/input/InputManager;->injectInputEvent(Landroid/view/InputEvent;I)Z

    invoke-virtual {v0}, Landroid/view/MotionEvent;->recycle()V

    return-void
.end method


# virtual methods
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .registers 7

    :try_start_0
    invoke-virtual {p2}, Landroid/content/Intent;->getAction()Ljava/lang/String;

    move-result-object v0

    const-string v1, "android.intent.action.SCREEN_OFF"

    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-eqz v1, :cond_1e

    const/4 v0, 0x0

    iput-boolean v0, p0, Lcom/android/server/port/PortGestures;->mPendingFp:Z

    const-wide/16 v0, 0x0

    iput-wide v0, p0, Lcom/android/server/port/PortGestures;->mLastTap:J

    invoke-direct {p0}, Lcom/android/server/port/PortGestures;->arm()V

    goto :goto_38

    :cond_1e
    # SCREEN_ON: just unregister; the long-press injection is timed by handleMessage(3)
    invoke-direct {p0}, Lcom/android/server/port/PortGestures;->disarm()V
    :try_end_38
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_38} :catch_39

    :goto_38
    return-void

    :catch_39
    move-exception v0

    const-string v1, "PortGestures"

    const-string v2, "onReceive failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method

# type: 1 = tap, 2 = long press on the fingerprint area
.method public onTrigger(I)V
    .registers 10

    :try_start_0
    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    const-string v1, "power"

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/os/PowerManager;

    invoke-virtual {v0}, Landroid/os/PowerManager;->isInteractive()Z

    move-result v1

    if-nez v1, :goto_a0

    invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J

    move-result-wide v2

    const/4 v1, 0x2

    if-ne p1, v1, :cond_34

    # long press: wake, then inject a press once the screen is on
    const-string v1, "PortGestures"

    const-string v4, "long press: wake + fingerprint"

    invoke-static {v1, v4}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    const/4 v1, 0x1

    iput-boolean v1, p0, Lcom/android/server/port/PortGestures;->mPendingFp:Z

    # PowerManager.WAKE_REASON_GESTURE
    const/4 v1, 0x4

    const-string v4, "port:udfps_long_press"

    invoke-virtual {v0, v2, v3, v1, v4}, Landroid/os/PowerManager;->wakeUp(JILjava/lang/String;)V

    const/4 v1, 0x0

    iput v1, p0, Lcom/android/server/port/PortGestures;->mPoll:I

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mHandler:Landroid/os/Handler;

    const/4 v1, 0x3

    const-wide/16 v4, 0x32

    invoke-virtual {v0, v1, v4, v5}, Landroid/os/Handler;->sendEmptyMessageDelayed(IJ)Z

    goto :goto_a0

    :cond_34
    iget-object v1, p0, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    invoke-virtual {v1}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v1

    const-string v4, "port_tap_wake"

    const/4 v5, 0x2

    invoke-static {v1, v4, v5}, Landroid/provider/Settings$Global;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I

    move-result v1

    const/4 v4, 0x1

    if-eq v1, v4, :cond_62

    iget-wide v4, p0, Lcom/android/server/port/PortGestures;->mLastTap:J

    const-wide/16 v6, 0x0

    cmp-long v1, v4, v6

    if-eqz v1, :cond_7a

    sub-long v4, v2, v4

    const-wide/16 v6, 0x258

    cmp-long v1, v4, v6

    if-gtz v1, :cond_7a

    # second tap within 600 ms (or port_tap_wake=1): wake
    :cond_62
    const-string v1, "PortGestures"

    const-string v4, "tap: wake"

    invoke-static {v1, v4}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    const-wide/16 v4, 0x0

    iput-wide v4, p0, Lcom/android/server/port/PortGestures;->mLastTap:J

    # PowerManager.WAKE_REASON_TAP
    const/16 v1, 0xf

    const-string v4, "port:double_tap"

    invoke-virtual {v0, v2, v3, v1, v4}, Landroid/os/PowerManager;->wakeUp(JILjava/lang/String;)V

    goto :goto_a0

    # first tap: remember the time, re-register for the second
    :cond_7a
    const-string v1, "PortGestures"

    const-string v4, "tap: first"

    invoke-static {v1, v4}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    iput-wide v2, p0, Lcom/android/server/port/PortGestures;->mLastTap:J

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mSensorManager:Landroid/hardware/SensorManager;

    iget-object v1, p0, Lcom/android/server/port/PortGestures;->mTapSensor:Landroid/hardware/Sensor;

    iget-object v4, p0, Lcom/android/server/port/PortGestures;->mTapListener:Lcom/android/server/port/PortGestures$L;

    if-eqz v0, :goto_a0

    if-eqz v1, :goto_a0

    invoke-virtual {v0, v4, v1}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z
    :try_end_a0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_a0} :catch_a1

    :goto_a0
    return-void

    :catch_a1
    move-exception v0

    const-string v1, "PortGestures"

    const-string v2, "onTrigger failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method

# what: 1 = press, 2 = release
.method public handleMessage(Landroid/os/Message;)Z
    .registers 9

    :try_start_0
    iget v0, p1, Landroid/os/Message;->what:I

    const/4 v1, 0x1

    if-ne v0, v1, :cond_40

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    const-string v1, "keyguard"

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/app/KeyguardManager;

    invoke-virtual {v0}, Landroid/app/KeyguardManager;->isKeyguardLocked()Z

    move-result v0

    if-eqz v0, :goto_5a

    const-string v0, "PortGestures"

    const-string v1, "fingerprint: pointer down"

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J

    move-result-wide v1

    iput-wide v1, p0, Lcom/android/server/port/PortGestures;->mDownTime:J

    move-wide v3, v1

    # MotionEvent.ACTION_DOWN
    const/4 v5, 0x0

    move-object v0, p0

    invoke-direct/range {v0 .. v5}, Lcom/android/server/port/PortGestures;->inject(JJI)V

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mHandler:Landroid/os/Handler;

    const/4 v1, 0x2

    const-wide/16 v2, 0x384

    invoke-virtual {v0, v1, v2, v3}, Landroid/os/Handler;->sendEmptyMessageDelayed(IJ)Z

    goto :goto_5a

    :cond_40
    const/4 v1, 0x2

    if-ne v0, v1, :cond_poll

    iget-wide v1, p0, Lcom/android/server/port/PortGestures;->mDownTime:J

    invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J

    move-result-wide v3

    # MotionEvent.ACTION_UP
    const/4 v5, 0x1

    move-object v0, p0

    invoke-direct/range {v0 .. v5}, Lcom/android/server/port/PortGestures;->inject(JJI)V

    goto :goto_5a

    # what 3: after a long-press wake, poll the display; 150 ms after Display.STATE_ON(2) send what 1 (press)
    :cond_poll
    const/4 v1, 0x3

    if-ne v0, v1, :goto_5a

    iget-boolean v0, p0, Lcom/android/server/port/PortGestures;->mPendingFp:Z

    if-eqz v0, :goto_5a

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mContext:Landroid/content/Context;

    const-string v1, "display"

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/hardware/display/DisplayManager;

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/hardware/display/DisplayManager;->getDisplay(I)Landroid/view/Display;

    move-result-object v0

    invoke-virtual {v0}, Landroid/view/Display;->getState()I

    move-result v0

    const/4 v1, 0x2

    if-ne v0, v1, :cond_notyet

    const/4 v0, 0x0

    iput-boolean v0, p0, Lcom/android/server/port/PortGestures;->mPendingFp:Z

    const-string v0, "PortGestures"

    const-string v1, "fingerprint: display on"

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mHandler:Landroid/os/Handler;

    const/4 v1, 0x1

    const-wide/16 v2, 0x96

    invoke-virtual {v0, v1, v2, v3}, Landroid/os/Handler;->sendEmptyMessageDelayed(IJ)Z

    goto :goto_5a

    :cond_notyet
    iget v0, p0, Lcom/android/server/port/PortGestures;->mPoll:I

    add-int/lit8 v0, v0, 0x1

    iput v0, p0, Lcom/android/server/port/PortGestures;->mPoll:I

    const/16 v1, 0x28

    if-lt v0, v1, :cond_again

    const/4 v0, 0x0

    iput-boolean v0, p0, Lcom/android/server/port/PortGestures;->mPendingFp:Z

    const-string v0, "PortGestures"

    const-string v1, "fingerprint: display not on after 2 s, give up"

    invoke-static {v0, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I

    goto :goto_5a

    :cond_again
    iget-object v0, p0, Lcom/android/server/port/PortGestures;->mHandler:Landroid/os/Handler;

    const/4 v1, 0x3

    const-wide/16 v2, 0x32

    invoke-virtual {v0, v1, v2, v3}, Landroid/os/Handler;->sendEmptyMessageDelayed(IJ)Z
    :try_end_5a
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_5a} :catch_5c

    :goto_5a
    const/4 v0, 0x1

    return v0

    :catch_5c
    move-exception v0

    const-string v1, "PortGestures"

    const-string v2, "handleMessage failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    const/4 v0, 0x1

    return v0
.end method
