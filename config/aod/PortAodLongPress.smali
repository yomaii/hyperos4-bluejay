.class public final Lcom/android/systemui/biometrics/PortAodLongPress;
.super Landroid/hardware/TriggerEventListener;
.source "PortAodLongPress.java"

# AOD long press on the fingerprint area, the AOSP way. Runs in SystemUI.
#
# On a Pixel, DozeSensors registers config_dozeUdfpsLongPressSensorType (com.google.sensor.long_press on the 6a) and
# DozeTriggers calls AuthController.onAodInterrupt -> UdfpsController.onFingerDown (illumination + fingerprint HAL)
# without touch events, so there is no wait for the screen. HyperOS uses its own DozeMachine and never registers
# the sensor, but the onAodInterrupt code is still there (inlined into DozeTriggers$$ExternalSyntheticLambda6).
#
# start() (from AuthController.start()) registers the one-shot sensor, re-armed after each event. With the screen off:
#   build UdfpsController$$ExternalSyntheticLambda1 like Lambda6 does (mIsAodInterruptActive, release after 1 s,
#   onFingerDown(requestId, -1, x, y, minor, major, 0, 0, 0, isAod=true)), run it now, then wake up.
#   The original also waits for the screen unless screen_off_udfps_enabled; this does not.
#   Position is the sensor center (540,1715), size 200x200. Sensor values are only logged.
# Only wakes up when fingerprint detection is not running.
# PortAodLongPress$Tap: tap with the screen off calls MiuiGxzwManager.notifyKeycodeGoto() to show the fingerprint
#   icon for a few seconds (it checks gxzw_icon_aod_show_enable itself). Double-tap to wake stays in PortGestures.
# Does nothing with Global port_udfps_mode=1 (PortGestures in system_server handles it).
# Log tag PortAodLongPress. Every entry point catches exceptions.


# static fields
.field private static sInstance:Lcom/android/systemui/biometrics/PortAodLongPress;


# instance fields
.field private final mAuth:Lcom/android/systemui/biometrics/AuthController;

.field private final mPm:Landroid/os/PowerManager;

.field private final mSensor:Landroid/hardware/Sensor;

.field private final mSm:Landroid/hardware/SensorManager;


# direct methods
.method private constructor <init>(Lcom/android/systemui/biometrics/AuthController;Landroid/hardware/SensorManager;Landroid/hardware/Sensor;Landroid/os/PowerManager;)V
    .registers 5

    invoke-direct {p0}, Landroid/hardware/TriggerEventListener;-><init>()V

    iput-object p1, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mAuth:Lcom/android/systemui/biometrics/AuthController;

    iput-object p2, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mSm:Landroid/hardware/SensorManager;

    iput-object p3, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mSensor:Landroid/hardware/Sensor;

    iput-object p4, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mPm:Landroid/os/PowerManager;

    return-void
.end method

.method public static start(Lcom/android/systemui/biometrics/AuthController;)V
    .registers 9

    :try_start_0
    sget-object v0, Lcom/android/systemui/biometrics/PortAodLongPress;->sInstance:Lcom/android/systemui/biometrics/PortAodLongPress;

    if-nez v0, :goto_ret

    iget-object v0, p0, Lcom/android/systemui/biometrics/AuthController;->mContext:Landroid/content/Context;

    const-string v1, "sensor"

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Landroid/hardware/SensorManager;

    const-string v2, "power"

    invoke-virtual {v0, v2}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v2

    check-cast v2, Landroid/os/PowerManager;

    const/4 v3, -0x1

    invoke-virtual {v1, v3}, Landroid/hardware/SensorManager;->getSensorList(I)Ljava/util/List;

    move-result-object v3

    invoke-interface {v3}, Ljava/util/List;->iterator()Ljava/util/Iterator;

    move-result-object v3

    :goto_loop
    invoke-interface {v3}, Ljava/util/Iterator;->hasNext()Z

    move-result v4

    if-eqz v4, :cond_none

    invoke-interface {v3}, Ljava/util/Iterator;->next()Ljava/lang/Object;

    move-result-object v4

    check-cast v4, Landroid/hardware/Sensor;

    invoke-virtual {v4}, Landroid/hardware/Sensor;->getStringType()Ljava/lang/String;

    move-result-object v5

    const-string v6, "com.google.sensor.long_press"

    invoke-virtual {v6, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v5

    if-eqz v5, :goto_loop

    new-instance v5, Lcom/android/systemui/biometrics/PortAodLongPress;

    invoke-direct {v5, p0, v1, v4, v2}, Lcom/android/systemui/biometrics/PortAodLongPress;-><init>(Lcom/android/systemui/biometrics/AuthController;Landroid/hardware/SensorManager;Landroid/hardware/Sensor;Landroid/os/PowerManager;)V

    sput-object v5, Lcom/android/systemui/biometrics/PortAodLongPress;->sInstance:Lcom/android/systemui/biometrics/PortAodLongPress;

    invoke-virtual {v1, v5, v4}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    const-string v0, "PortAodLongPress"

    const-string v4, "armed com.google.sensor.long_press"

    invoke-static {v0, v4}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    # tap: show the fingerprint icon on AOD
    const-string v4, "com.google.sensor.single_touch"

    invoke-static {v1, v4}, Lcom/android/systemui/biometrics/PortAodLongPress;->findSensor(Landroid/hardware/SensorManager;Ljava/lang/String;)Landroid/hardware/Sensor;

    move-result-object v4

    if-eqz v4, :cond_pickup

    new-instance v5, Lcom/android/systemui/biometrics/PortAodLongPress$Tap;

    invoke-direct {v5, v1, v4, v2}, Lcom/android/systemui/biometrics/PortAodLongPress$Tap;-><init>(Landroid/hardware/SensorManager;Landroid/hardware/Sensor;Landroid/os/PowerManager;)V

    invoke-virtual {v1, v5, v4}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    const-string v4, "armed com.google.sensor.single_touch (fingerprint icon)"

    invoke-static {v0, v4}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    # lift to wake, see PortAodLongPress$Pickup
    :cond_pickup
    const-string v4, "android.sensor.pick_up_gesture"

    invoke-static {v1, v4}, Lcom/android/systemui/biometrics/PortAodLongPress;->findSensor(Landroid/hardware/SensorManager;Ljava/lang/String;)Landroid/hardware/Sensor;

    move-result-object v4

    if-eqz v4, :goto_ret

    iget-object v6, p0, Lcom/android/systemui/biometrics/AuthController;->mContext:Landroid/content/Context;

    invoke-virtual {v6}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v6

    new-instance v5, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;

    invoke-direct {v5, v1, v4, v2, v6}, Lcom/android/systemui/biometrics/PortAodLongPress$Pickup;-><init>(Landroid/hardware/SensorManager;Landroid/hardware/Sensor;Landroid/os/PowerManager;Landroid/content/ContentResolver;)V

    invoke-virtual {v1, v5, v4}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    const-string v4, "armed android.sensor.pick_up_gesture (pickup wake)"

    invoke-static {v0, v4}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    goto :goto_ret

    :cond_none
    const-string v0, "PortAodLongPress"

    const-string v1, "no com.google.sensor.long_press sensor"

    invoke-static {v0, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :goto_ret
    return-void

    :catch_0
    move-exception v0

    const-string v1, "PortAodLongPress"

    const-string v2, "start failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method


.method static findSensor(Landroid/hardware/SensorManager;Ljava/lang/String;)Landroid/hardware/Sensor;
    .registers 5

    const/4 v0, -0x1

    invoke-virtual {p0, v0}, Landroid/hardware/SensorManager;->getSensorList(I)Ljava/util/List;

    move-result-object v0

    invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;

    move-result-object v0

    :goto_loop
    invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z

    move-result v1

    if-eqz v1, :cond_none

    invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Landroid/hardware/Sensor;

    invoke-virtual {v1}, Landroid/hardware/Sensor;->getStringType()Ljava/lang/String;

    move-result-object v2

    invoke-virtual {p1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v2

    if-eqz v2, :goto_loop

    return-object v1

    :cond_none
    const/4 v0, 0x0

    return-object v0
.end method


# virtual methods
.method public onTrigger(Landroid/hardware/TriggerEvent;)V
    .registers 10

    :try_start_0
    # one-shot sensor: re-arm first
    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mSm:Landroid/hardware/SensorManager;

    iget-object v1, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mSensor:Landroid/hardware/Sensor;

    invoke-virtual {v0, p0, v1}, Landroid/hardware/SensorManager;->requestTriggerSensor(Landroid/hardware/TriggerEventListener;Landroid/hardware/Sensor;)Z

    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mAuth:Lcom/android/systemui/biometrics/AuthController;

    iget-object v0, v0, Lcom/android/systemui/biometrics/AuthController;->mContext:Landroid/content/Context;

    invoke-virtual {v0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v0

    const-string v1, "port_udfps_mode"

    const/4 v2, 0x0

    invoke-static {v0, v1, v2}, Landroid/provider/Settings$Global;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I

    move-result v0

    if-nez v0, :goto_ret

    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mPm:Landroid/os/PowerManager;

    invoke-virtual {v0}, Landroid/os/PowerManager;->isInteractive()Z

    move-result v0

    if-nez v0, :goto_ret

    const-string v0, "PortAodLongPress"

    iget-object v1, p1, Landroid/hardware/TriggerEvent;->values:[F

    invoke-static {v1}, Ljava/util/Arrays;->toString([F)Ljava/lang/String;

    move-result-object v1

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    # as in DozeTriggers$$ExternalSyntheticLambda6 (inlined AuthController.onAodInterrupt)
    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mAuth:Lcom/android/systemui/biometrics/AuthController;

    iget-object v0, v0, Lcom/android/systemui/biometrics/AuthController;->mUdfpsController:Lcom/android/systemui/biometrics/UdfpsController;

    if-eqz v0, :goto_wake

    iget-boolean v1, v0, Lcom/android/systemui/biometrics/UdfpsController;->mIsAodInterruptActive:Z

    if-nez v1, :goto_wake

    iget-object v1, v0, Lcom/android/systemui/biometrics/UdfpsController;->mKeyguardUpdateMonitor:Lcom/android/keyguard/KeyguardUpdateMonitor;

    invoke-virtual {v1}, Lcom/android/keyguard/KeyguardUpdateMonitor;->isFingerprintDetectionRunning()Z

    move-result v1

    if-nez v1, :cond_running

    const-string v1, "PortAodLongPress"

    const-string v2, "fingerprint detection not running, wake only"

    invoke-static {v1, v2}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I

    goto :goto_wake

    :cond_running
    iget-object v1, v0, Lcom/android/systemui/biometrics/UdfpsController;->mOverlay:Lcom/android/systemui/biometrics/UdfpsControllerOverlay;

    const-wide/16 v2, -0x1

    if-eqz v1, :cond_noov

    iget-wide v2, v1, Lcom/android/systemui/biometrics/UdfpsControllerOverlay;->requestId:J

    :cond_noov
    new-instance v4, Lcom/android/systemui/biometrics/UdfpsController$$ExternalSyntheticLambda1;

    invoke-direct {v4}, Ljava/lang/Object;-><init>()V

    iput-object v0, v4, Lcom/android/systemui/biometrics/UdfpsController$$ExternalSyntheticLambda1;->f$0:Lcom/android/systemui/biometrics/UdfpsController;

    iput-wide v2, v4, Lcom/android/systemui/biometrics/UdfpsController$$ExternalSyntheticLambda1;->f$1:J

    # x = 540, y = 1715 (sensor center)
    const/16 v5, 0x21c

    iput v5, v4, Lcom/android/systemui/biometrics/UdfpsController$$ExternalSyntheticLambda1;->f$2:I

    const/16 v5, 0x6b3

    iput v5, v4, Lcom/android/systemui/biometrics/UdfpsController$$ExternalSyntheticLambda1;->f$3:I

    # minor, major = 200.0f
    const/high16 v5, 0x43480000

    iput v5, v4, Lcom/android/systemui/biometrics/UdfpsController$$ExternalSyntheticLambda1;->f$4:F

    iput v5, v4, Lcom/android/systemui/biometrics/UdfpsController$$ExternalSyntheticLambda1;->f$5:F

    invoke-virtual {v4}, Lcom/android/systemui/biometrics/UdfpsController$$ExternalSyntheticLambda1;->run()V

    const-string v1, "PortAodLongPress"

    const-string v2, "aod interrupt: finger down"

    invoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    :goto_wake
    iget-object v0, p0, Lcom/android/systemui/biometrics/PortAodLongPress;->mPm:Landroid/os/PowerManager;

    invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J

    move-result-wide v1

    # PowerManager.WAKE_REASON_GESTURE
    const/4 v3, 0x4

    const-string v4, "port:udfps_aod"

    invoke-virtual {v0, v1, v2, v3, v4}, Landroid/os/PowerManager;->wakeUp(JILjava/lang/String;)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :goto_ret
    return-void

    :catch_0
    move-exception v0

    const-string v1, "PortAodLongPress"

    const-string v2, "onTrigger failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    return-void
.end method
